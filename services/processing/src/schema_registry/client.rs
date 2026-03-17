// src/schema_registry/client.rs
// أضف في Cargo.toml:
//   reqwest = { version = "0.12", features = ["json"] }
//   serde = { version = "1", features = ["derive"] }
//   serde_json = "1"
//   anyhow = "1"
//   tokio = { version = "1", features = ["full"] }
//   tracing = "0.1"

use anyhow::{anyhow, Context, Result};
use reqwest::Client;
use serde::{Deserialize, Serialize};
use std::time::Duration;
use tracing::{info, warn};

#[derive(Debug, Clone)]
pub struct SchemaRegistryClient {
    base_url: String,
    client: Client,
}

#[derive(Debug, Serialize)]
struct SchemaRequest<'a> {
    schema: &'a str,
    #[serde(rename = "schemaType")]
    schema_type: &'a str,
}

#[derive(Debug, Deserialize)]
struct SchemaIdResponse {
    id: i32,
}

#[derive(Debug, Deserialize)]
struct LatestSchemaResponse {
    pub id: i32,
    pub version: i32,
    pub schema: String,
}

#[derive(Debug, Deserialize)]
struct CompatibilityResponse {
    is_compatible: bool,
}

impl SchemaRegistryClient {
    /// ينشئ client جديد
    pub fn new(base_url: impl Into<String>) -> Result<Self> {
        let client = Client::builder()
            .timeout(Duration::from_secs(10))
            .build()
            .context("build http client")?;

        Ok(Self {
            base_url: base_url.into(),
            client,
        })
    }

    /// ينتظر الـ Schema Registry يكون ready (max 60 ثانية)
    pub async fn wait_for_ready(&self) -> Result<()> {
        info!("waiting for schema registry at {}", self.base_url);
        for attempt in 1..=30 {
            match self.list_subjects().await {
                Ok(_) => {
                    info!("schema registry is ready");
                    return Ok(());
                }
                Err(e) => {
                    warn!("schema registry not ready (attempt {}/30): {}", attempt, e);
                    tokio::time::sleep(Duration::from_secs(2)).await;
                }
            }
        }
        Err(anyhow!("schema registry not ready after 60 seconds"))
    }

    /// يسجل schema ويرجع الـ ID
    pub async fn register_schema(&self, subject: &str, schema: &str) -> Result<i32> {
        let url = format!("{}/subjects/{}/versions", self.base_url, subject);

        let resp = self
            .client
            .post(&url)
            .header("Content-Type", "application/vnd.schemaregistry.v1+json")
            .json(&SchemaRequest {
                schema,
                schema_type: "PROTOBUF",
            })
            .send()
            .await
            .context("send register request")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("register failed {}: {}", status, text));
        }

        let result: SchemaIdResponse = resp.json().await.context("decode register response")?;
        info!("schema registered: subject={} id={}", subject, result.id);
        Ok(result.id)
    }

    /// يجيب آخر schema version
    pub async fn get_latest_schema(&self, subject: &str) -> Result<LatestSchemaResponse> {
        let url = format!("{}/subjects/{}/versions/latest", self.base_url, subject);

        let resp = self
            .client
            .get(&url)
            .send()
            .await
            .context("get latest schema")?;

        if resp.status() == 404 {
            return Err(anyhow!("subject '{}' not found in registry", subject));
        }
        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("get schema failed {}: {}", status, text));
        }

        resp.json().await.context("decode schema response")
    }

    /// يتحقق من compatibility قبل التسجيل
    pub async fn check_compatibility(&self, subject: &str, schema: &str) -> Result<bool> {
        let url = format!(
            "{}/compatibility/subjects/{}/versions/latest",
            self.base_url, subject
        );

        let resp = self
            .client
            .post(&url)
            .header("Content-Type", "application/vnd.schemaregistry.v1+json")
            .json(&SchemaRequest {
                schema,
                schema_type: "PROTOBUF",
            })
            .send()
            .await
            .context("compatibility check request")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("compatibility check failed {}: {}", status, text));
        }

        let result: CompatibilityResponse =
            resp.json().await.context("decode compatibility response")?;
        Ok(result.is_compatible)
    }

    /// يجيب كل الـ subjects المسجلة
    pub async fn list_subjects(&self) -> Result<Vec<String>> {
        let url = format!("{}/subjects", self.base_url);

        let resp = self
            .client
            .get(&url)
            .send()
            .await
            .context("list subjects request")?;

        if !resp.status().is_success() {
            let status = resp.status();
            let text = resp.text().await.unwrap_or_default();
            return Err(anyhow!("list subjects failed {}: {}", status, text));
        }

        resp.json().await.context("decode subjects response")
    }
}
