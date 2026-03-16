//! Kafka / Redpanda consumer — placeholder
//!
//! This module will house the Redpanda consumer that reads MarketEvents
//! from Kafka topics and forwards them to the ProcessingEngine gRPC service.
//! Implementation is tracked as a follow-up task.

#![allow(dead_code)]

/// Consumer configuration loaded from environment variables.
#[derive(Debug)]
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
                .unwrap_or_else(|_| "processing:50051".into()),
        }
    }
}
