use anyhow::{anyhow, Result};
use serde_json::Value;
use sqlx::SqlitePool;

use crate::forwarding::route_selector::RouteSelector;

#[derive(Debug, Clone)]
pub struct ResolvedTarget {
    pub provider_id: String,
    pub upstream_protocol: String,
    pub base_url: String,
    pub api_key: String,
    pub effective_model: Option<String>,
    pub protocol_config: Value,
}

#[derive(Clone)]
pub struct TargetResolver {
    pool: SqlitePool,
}

impl TargetResolver {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn resolve(&self, gateway_id: &str) -> Result<ResolvedTarget> {
        let selector = RouteSelector::new(self.pool.clone());
        selector
            .select(gateway_id)
            .await
            .map_err(|_| anyhow!("gateway not found: {gateway_id}"))
    }
}
