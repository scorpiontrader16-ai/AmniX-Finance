//! Kafka / Redpanda consumer
//!
//! Reads MarketEvents from a Kafka topic (protobuf-encoded),
//! deserializes them, and forwards each event to the ProcessingEngine
//! via gRPC (ProcessEvent RPC).

use std::time::Duration;

use prost::Message;
use rdkafka::{
    config::ClientConfig,
    consumer::{CommitMode, Consumer, StreamConsumer},
    message::BorrowedMessage,
    Message as KafkaMessage,
};
use tokio::time::sleep;
use tonic::transport::Channel;
use tracing::{error, info, instrument, warn};

use crate::grpc::processing_v1::{
    processing_engine_service_client::ProcessingEngineServiceClient,
    ProcessEventRequest, ProcessingConfig,
};
use crate::ingestion::v1::MarketEvent;

// ── Config ────────────────────────────────────────────────────────────────
#[derive(Debug, Clone)]
pub struct ConsumerConfig {
    pub brokers:         String,
    pub group_id:        String,
    pub topic:           String,
    pub processing_addr: String,
}

impl ConsumerConfig {
    pub fn from_env() -> Self {
        Self {
            brokers: std::env::var("REDPANDA_BROKERS")
                .unwrap_or_else(|_| "redpanda:9092".into()),
            group_id: std::env::var("KAFKA_GROUP_ID")
                .unwrap_or_else(|_| "processing-consumer".into()),
            topic: std::env::var("KAFKA_TOPIC")
                .unwrap_or_else(|_| "market-events".into()),
            processing_addr: std::env::var("PROCESSING_ADDR")
                .unwrap_or_else(|_| "http://processing:50051".into()),
        }
    }
}

// ── Consumer ──────────────────────────────────────────────────────────────
pub struct KafkaConsumer {
    consumer: StreamConsumer,
    client:   ProcessingEngineServiceClient<Channel>,
    /// Retained for future use (e.g. dynamic topic reload)
    #[allow(dead_code)]
    config:   ConsumerConfig,
}

impl KafkaConsumer {
    /// Build the Kafka consumer and connect to the gRPC server.
    /// Retries the gRPC connection up to 5 times with backoff.
    pub async fn new(config: ConsumerConfig) -> Result<Self, Box<dyn std::error::Error>> {
        // ── Kafka ──────────────────────────────────────────────────────────
        let consumer: StreamConsumer = ClientConfig::new()
            .set("bootstrap.servers",       &config.brokers)
            .set("group.id",                &config.group_id)
            .set("enable.auto.commit",      "false")
            .set("auto.offset.reset",       "earliest")
            .set("session.timeout.ms",      "30000")
            .set("max.poll.interval.ms",    "300000")
            .set("fetch.max.bytes",         "10485760") // 10 MB
            .create()?;

        consumer.subscribe(&[&config.topic])?;
        info!(topic = %config.topic, brokers = %config.brokers, "Kafka consumer subscribed");

        // ── gRPC client with retry ─────────────────────────────────────────
        let client = connect_with_retry(&config.processing_addr, 5).await?;

        Ok(Self { consumer, client, config })
    }

    /// Main loop — runs until the provided shutdown future resolves.
    pub async fn run(mut self, mut shutdown: tokio::sync::watch::Receiver<bool>) {
        info!("consumer loop started");

        loop {
            tokio::select! {
                // Shutdown signal
                _ = shutdown.changed() => {
                    if *shutdown.borrow() {
                        info!("consumer received shutdown signal");
                        break;
                    }
                }

                // Next Kafka message
                result = self.consumer.recv() => {
                    match result {
                        Err(e) => {
                            error!(error = %e, "kafka receive error");
                            sleep(Duration::from_millis(500)).await;
                        }
                        Ok(msg) => {
                            self.handle_message(&msg).await;
                            // Manual commit after successful processing
                            if let Err(e) = self.consumer.commit_message(&msg, CommitMode::Async) {
                                warn!(error = %e, "commit failed");
                            }
                        }
                    }
                }
            }
        }

        info!("consumer loop stopped");
    }

    /// Deserialize the message payload and forward it to the gRPC server.
    #[instrument(skip(self, msg), fields(
        topic     = %msg.topic(),
        partition = msg.partition(),
        offset    = msg.offset(),
    ))]
    async fn handle_message(&mut self, msg: &BorrowedMessage<'_>) {
        let payload = match msg.payload() {
            Some(p) => p,
            None => {
                warn!("empty payload — skipping");
                return;
            }
        };

        // Decode protobuf-encoded MarketEvent
        let event = match MarketEvent::decode(payload) {
            Ok(e)  => e,
            Err(e) => {
                error!(error = %e, "protobuf decode failed");
                return;
            }
        };

        info!(
            event_id = %event.event_id,
            symbol   = %event.symbol,
            "forwarding event to processing engine"
        );

        let request = ProcessEventRequest {
            event:  Some(event),
            config: Some(default_processing_config()),
        };

        match self.client.process_event(request).await {
            Ok(response) => {
                let r = response.into_inner();
                info!(
                    event_id          = %r.event_id,
                    correlation_score = r.correlation_score,
                    processing_us     = r.processing_us,
                    "event processed successfully"
                );
            }
            Err(e) => {
                error!(error = %e, "gRPC process_event failed");
            }
        }
    }
}

// ── Helpers ───────────────────────────────────────────────────────────────

/// Connect to the gRPC server with exponential backoff.
async fn connect_with_retry(
    addr: &str,
    max_retries: u32,
) -> Result<ProcessingEngineServiceClient<Channel>, Box<dyn std::error::Error>> {
    let mut delay = Duration::from_secs(1);

    for attempt in 1..=max_retries {
        match Channel::from_shared(addr.to_string())
            .map_err(|e| format!("invalid gRPC address: {e}"))?
            .connect()
            .await
        {
            Ok(channel) => {
                info!(addr, "connected to processing gRPC server");
                return Ok(ProcessingEngineServiceClient::new(channel));
            }
            Err(e) => {
                if attempt == max_retries {
                    return Err(format!(
                        "failed to connect to {} after {} attempts: {}",
                        addr, max_retries, e
                    )
                    .into());
                }
                warn!(
                    addr,
                    attempt,
                    max_retries,
                    delay_secs = delay.as_secs(),
                    error = %e,
                    "gRPC connection failed, retrying"
                );
                sleep(delay).await;
                delay = (delay * 2).min(Duration::from_secs(30));
            }
        }
    }

    unreachable!()
}

fn default_processing_config() -> ProcessingConfig {
    ProcessingConfig {
        indicators:        vec![
            "rsi".into(),
            "macd".into(),
            "correlation".into(),
        ],
        lookback_periods:  14,
        include_sentiment: false,
    }
}
