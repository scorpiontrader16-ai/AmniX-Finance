//! gRPC handlers — activated after: buf generate proto
//!
//! Steps to enable:
//! 1. Run: buf generate proto
//! 2. Add: mod gen; in main.rs
//! 3. Uncomment: mod grpc; in main.rs
//! 4. Add gRPC Server::builder() in main alongside HTTP server

use tonic::Status;
use crate::engine::EngineError;

impl From<EngineError> for Status {
    fn from(err: EngineError) -> Self {
        match err {
            EngineError::InsufficientData { .. } =>
                Status::invalid_argument(err.to_string()),
            EngineError::InvalidSymbol(_) =>
                Status::invalid_argument(err.to_string()),
            EngineError::Computation(_) =>
                Status::internal(err.to_string()),
        }
    }
}
