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
use prometheus::{
    register_counter_vec, register_histogram_vec, register_gauge,
    CounterVec, HistogramVec, Gauge, Encoder, TextEncoder,
};
use tokio::signal;
use tokio_stream::wrappers::TcpListenerStream;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod engine;
mod consumer;
mod grpc;

pub mod ingestion {
    pub mod v1 {
        tonic::include_proto!("ingestion.v1");
    }
}

// ── Prometheus Metrics ────────────────────────────────────────────────────

pub struct Metrics {
    pub grpc_requests_total:    CounterVec,
    pub grpc_request_duration:  HistogramVec,
    pub kafka_messages_total:   CounterVec,
    pub kafka_errors_total:     CounterVec,
    pub circuit_breaker_state:  Gauge,
    pub events_processed_total: CounterVec,
}

impl Metrics {
    pub fn new() -> Result<Self, prometheus::Error> {
        Ok(Self {
            grpc_requests_total: register_counter_vec!(
                "processing_grpc_requests_total",
                "Total gRPC requests by method and status",
                &["method", "status"]
            )?,
            grpc_request_duration: register_histogram_vec!(
                "processing_grpc_request_duration_seconds",
                "gRPC request duration in seconds",
                &["method"],
                vec![0.001, 0.005, 0.01, 0.05, 0.1, 0.5, 1.0]
            )?,
            kafka_messages_total: register_counter_vec!(
                "processing_kafka_messages_total",
                "Total Kafka messages consumed by status",
                &["status"]
            )?,
            kafka_errors_total: register_counter_vec!(
                "processing_kafka_errors_total",
                "Total Kafka errors by type",
                &["error_type"]
            )?,
            circuit_breaker_state: register_gauge!(
                "processing_circuit_breaker_open",
                "1 if circuit breaker is open, 0 if closed"
            )?,
            events_processed_total: register_counter_vec!(
                "processing_events_processed_total",
                "Total events processed by type",
                &["event_type"]
            )?,
        })
    }
}

impl Default for Metrics {
    fn default() -> Self {
        Self::new().expect("failed to register metrics")
    }
}

// ── Health state ──────────────────────────────────────────────────────────

#[derive(Clone)]
pub struct AppState {
    pub grpc_ready:  Arc<AtomicBool>,
    pub kafka_ready: Arc<AtomicBool>,
    /// Held here to keep the Arc alive for the full process lifetime.
    /// Actual metric updates happen inside Engine and KafkaConsumer.
    #[allow(dead_code)]
    pub metrics: Arc<Metrics>,
}

impl AppState {
    pub fn new(metrics: Arc<Metrics>) -> Self {
        Self {
            grpc_ready:  Arc::new(AtomicBool::new(false)),
            kafka_ready: Arc::new(AtomicBool::new(false)),
            metrics,
        }
    }
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

    let metrics = Arc::new(Metrics::new()?);
    let state   = AppState::new(metrics.clone());

    // ── Shutdown channel ──────────────────────────────────────────────────
    let (shutdown_tx, shutdown_rx) = tokio::sync::watch::channel(false);

    // ── gRPC server ───────────────────────────────────────────────────────
    let grpc_addr: SocketAddr = format!("0.0.0.0:{}", config.grpc_port)
        .parse()
        .map_err(|e| format!("invalid gRPC address: {e}"))?;

    let grpc_listener = tokio::net::TcpListener::bind(grpc_addr).await
        .map_err(|e| format!("failed to bind gRPC port {}: {}", config.grpc_port, e))?;

    let reflection = tonic_reflection::server::Builder::configure()
        .register_encoded_file_descriptor_set(grpc::processing_v1::FILE_DESCRIPTOR_SET)
        .build_v1()
        .map_err(|e| format!("reflection build error: {e}"))?;

    let engine = grpc::Engine::new(metrics.clone());

    state.grpc_ready.store(true, Ordering::Relaxed);
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
    match consumer::KafkaConsumer::new(consumer_config, metrics.clone()).await {
        Ok(kafka) => {
            state.kafka_ready.store(true, Ordering::Relaxed);
            info!("Kafka consumer connected and ready");
            let rx = shutdown_rx.clone();
            tokio::spawn(async move {
                kafka.run(rx).await;
            });
        }
        Err(e) => {
            tracing::warn!(
                error = %e,
                "Kafka consumer failed to start — readyz will report not-ready"
            );
        }
    }
    drop(shutdown_rx);

    // ── HTTP server ───────────────────────────────────────────────────────
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

    run_http_server(metrics_addr, state, shutdown).await?;
    info!("shutdown complete");
    Ok(())
}

// ── HTTP server ───────────────────────────────────────────────────────────
async fn run_http_server(
    addr:     SocketAddr,
    state:    AppState,
    shutdown: impl std::future::Future<Output = ()> + Send + 'static,
) -> Result<(), Box<dyn std::error::Error>> {
    let app = Router::new()
        .route("/healthz", get(healthz))
        .route("/readyz",  get(readyz))
        .route("/metrics", get(metrics_handler))
        .with_state(state);

    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!(port = addr.port(), "HTTP server listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown)
        .await?;

    Ok(())
}

// ── Health handlers ───────────────────────────────────────────────────────

async fn healthz() -> impl IntoResponse {
    StatusCode::OK
}

async fn readyz(State(state): State<AppState>) -> impl IntoResponse {
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

/// Real Prometheus metrics endpoint
async fn metrics_handler() -> impl IntoResponse {
    let encoder = TextEncoder::new();
    let metric_families = prometheus::gather();
    let mut buffer = Vec::new();
    encoder.encode(&metric_families, &mut buffer)
        .unwrap_or_default();
    (
        StatusCode::OK,
        [(axum::http::header::CONTENT_TYPE, "text/plain; version=0.0.4")],
        buffer,
    )
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
