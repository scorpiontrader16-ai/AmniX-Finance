//! Processing Service — HTTP health + metrics server
//! gRPC server activates after: buf generate proto

use std::net::SocketAddr;

use tokio::signal;
use tracing::info;
use tracing_subscriber::{layer::SubscriberExt, util::SubscriberInitExt};

mod engine;
mod consumer;
mod grpc;

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
        version = env!("CARGO_PKG_VERSION"),
        grpc_port    = config.grpc_port,
        metrics_port = config.metrics_port,
        "starting processing service"
    );

    let metrics_addr: SocketAddr = format!("0.0.0.0:{}", config.metrics_port)
        .parse()
        .map_err(|e| format!("invalid metrics address: {e}"))?;

    // Graceful shutdown on SIGTERM or Ctrl-C
    let shutdown = async {
        match signal::ctrl_c().await {
            Ok(()) => info!("shutdown signal received"),
            Err(e) => tracing::error!(error = %e, "ctrl_c listener error"),
        }
    };

    run_http_server(metrics_addr, shutdown).await?;

    info!("shutdown complete");
    Ok(())
}

async fn run_http_server(
    addr: SocketAddr,
    shutdown: impl std::future::Future<Output = ()>,
) -> Result<(), Box<dyn std::error::Error>> {
    use axum::{routing::get, Router};

    let app = Router::new()
        .route("/healthz", get(|| async { "ok" }))
        .route("/readyz",  get(|| async { "ready" }))
        .route("/metrics", get(|| async { "# metrics\n" }));

    let listener = tokio::net::TcpListener::bind(addr).await?;
    info!(port = addr.port(), "HTTP server listening");

    axum::serve(listener, app)
        .with_graceful_shutdown(shutdown)
        .await?;

    Ok(())
}

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
        Ok(v) => v.parse::<u16>()
            .map_err(|_| format!("{key} must be 1-65535, got: {v}")),
        Err(_) => Ok(default),
    }
}
