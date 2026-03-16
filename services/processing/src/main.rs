//! Processing Service — HTTP health/metrics + gRPC server + Kafka consumer
use std::net::SocketAddr;
use std::sync::{
    atomic::{AtomicBool, Ordering},
    Arc,
};

use axum::{
    extract::State,
    http::StatusCode,
    response::IntoResponse,
    routing::get,
    Router,
};
use tokio::signal;
use tokio_stream::wrappers::TcpListenerStream;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod engine;
mod consumer;
mod grpc;

// ingestion::v1 MUST be at crate root.
// processing.v1.rs references super::super::ingestion::v1::MarketEvent.
// processing_v1 is at crate::grpc::processing_v1, so:
//   super::super = crate  →  crate::ingestion::v1  ✅
pub mod ingestion {
    pub mod v1 {
        tonic::include_proto!("ingestion.v1");
    }
}

// ── Health state ──────────────────────────────────────────────────────────
/// Shared readiness flags updated by each subsystem.
/// Kubernetes calls /readyz — returns 503 until all flags are true.
/// Kubernetes calls /healthz — always 200 (liveness, process is alive).
#[derive(Clone)]
pub struct HealthState {
    pub grpc_ready:  Arc<AtomicBool>,
    pub kafka_ready: Arc<AtomicBool>,
}

impl HealthState {
    pub fn new() -> Self {
        Self {
            grpc_ready:  Arc::new(AtomicBool::new(false)),
            kafka_ready: Arc::new(AtomicBool::new(false)),
        }
    }
}

impl Default for HealthState {
    fn default() -> Self { Self::new() }
}

#[tokio::main]
async fn main() -> Result<(), Box<dyn std::error::Error>> {
    tracing_subscriber::registry()
        .with(tracing_subscriber::EnvFilter::new(
            std::env::var("RUST_LOG").unwrap_or_else(|_| "info".into()),
        ))
        .with(tracing_subscriber::fmt::layer().json())
        .init();

    let config = Config::from_env()?;

    info!(
        version      = env!("CARGO_PKG_VERSION"),
        grpc_port    = config.grpc_port,
        metrics_port = config.metrics_port,
        "starting processing service"
    );

    let health = HealthState::new();

    // ── Shutdown channel ──────────────────────────────────────────────────
    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);

    // ── gRPC server ───────────────────────────────────────────────────────
    // Bind the TCP listener BEFORE spawning so we can set grpc_ready
    // immediately after the port is open — no race condition.
    let grpc_addr: SocketAddr = format!("0.0.0.0:{}", config.grpc_port)
        .parse()
        .map_err(|e| format!("invalid gRPC address: {e}"))?;

    let grpc_listener = tokio::net::TcpListener::bind(grpc_addr).await
        .map_err(|e| format!("failed to bind gRPC port {}: {}", config.grpc_port, e))?;

    let reflection = tonic_reflection::server::Builder::configure()
        .register_encoded_file_descriptor_set(grpc::processing_v1::FILE_DESCRIPTOR_SET)
        .build_v1()
        .map_err(|e| format!("reflection build error: {e}"))?;

    let engine = grpc::Engine::new();

    // Port is bound — gRPC is ready to accept connections
    health.grpc_ready.store(true, Ordering::Relaxed);
    info!(port = config.grpc_port, "gRPC server listening");

    tokio::spawn(async move {
        tonic::transport::Server::builder()
            .add_service(engine.into_server())
            .add_service(reflection)
            .serve_with_incoming(TcpListenerStream::new(grpc_listener))
            .await
            .expect("gRPC server failed");
    });

    // ── Kafka consumer ────────────────────────────────────────────────────
    let consumer_config = consumer::ConsumerConfig::from_env();
    match consumer::KafkaConsumer::new(consumer_config).await {
        Ok(kafka) => {
            health.kafka_ready.store(true, Ordering::Relaxed);
            info!("Kafka consumer connected and ready");
            let rx = shutdown_rx.clone();
            tokio::spawn(async move {
                kafka.run(rx).await;
            });
        }
        Err(e) => {
            // Log but don't crash — service still serves gRPC without Kafka.
            // /readyz will return 503 until Kafka is available.
            tracing::warn!(
                error = %e,
                "Kafka consumer failed to start — readyz will report not-ready"
            );
        }
    }
    // shutdown_rx kept alive until end of main so the watch channel stays open
    drop(shutdown_rx);

    // ── HTTP server (health + metrics) ────────────────────────────────────
    let metrics_addr: SocketAddr = format!("0.0.0.0:{}", config.metrics_port)
        .parse()
        .map_err(|e| format!("invalid metrics address: {e}"))?;

    let shutdown = async move {
        match signal::ctrl_c().await {
            Ok(())  => info!("shutdown signal received"),
            Err(e)  => tracing::error!(error = %e, "ctrl_c listener error"),
        }
        let _ = shutdown_tx.send(true);
    };

    run_http_server(metrics_addr, health, shutdown).await?;
    info!("shutdown complete");
    Ok(())
}

// ── HTTP server ───────────────────────────────────────────────────────────
async fn run_http_server(
    addr:     SocketAddr,
    health:   HealthState,
    shutdown: impl std::future::Future<Output = ()> + Send + 'static,
) -> Result<(), Box<dyn std::error::Error>> {
    let app = Router::new()
        // Liveness — always 200 if the process is alive
        .route("/healthz", get(healthz))
        // Readiness — 200 only when gRPC + Kafka are both ready
        .route("/readyz",  get(readyz))
        // Metrics placeholder (replaced in next milestone with real Prometheus)
        .route("/metrics", get(|| async { "# metrics\n" }))
        .with_state(health);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!(port = addr.port(), "HTTP server listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown)
        .await?;

    Ok(())
}

// ── Health handlers ───────────────────────────────────────────────────────

/// Liveness probe — Kubernetes restarts the pod if this fails.
/// Returns 200 as long as the process is running.
async fn healthz() -> impl IntoResponse {
    StatusCode::OK
}

/// Readiness probe — Kubernetes stops sending traffic if this fails.
/// Returns 200 only when ALL subsystems are ready.
async fn readyz(State(state): State<HealthState>) -> impl IntoResponse {
    let grpc_ok  = state.grpc_ready.load(Ordering::Relaxed);
    let kafka_ok = state.kafka_ready.load(Ordering::Relaxed);

    if grpc_ok && kafka_ok {
        (StatusCode::OK, "ready")
    } else {
        let reason = if !grpc_ok { "grpc not ready" } else { "kafka not ready" };
        tracing::warn!(reason, "readyz check failed");
        (StatusCode::SERVICE_UNAVAILABLE, reason)
    }
}

// ── Config ────────────────────────────────────────────────────────────────
#[derive(Debug)]
pub struct Config {
    pub grpc_port:        u16,
    pub metrics_port:     u16,
    pub redpanda_brokers: String,
}

impl Config {
    pub fn from_env() -> Result<Self, String> {
        Ok(Self {
            grpc_port:        parse_port("GRPC_PORT",    50051)?,
            metrics_port:     parse_port("METRICS_PORT", 9090)?,
            redpanda_brokers: std::env::var("REDPANDA_BROKERS")
                .unwrap_or_else(|_| "redpanda:9092".into()),
        })
    }
}

fn parse_port(key: &str, default: u16) -> Result<u16, String> {
    match std::env::var(key) {
        Ok(v) => v
            .parse::<u16>()
            .map_err(|_| format!("{key} must be 1-65535, got: {v}")),
        Err(_) => Ok(default),
    }
}
