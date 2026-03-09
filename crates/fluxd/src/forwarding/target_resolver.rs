use anyhow::{anyhow, Result};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

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
        let row = sqlx::query(
            r#"
            SELECT
                p.id AS provider_id,
                p.kind AS provider_kind,
                p.base_url,
                p.api_key,
                g.upstream_protocol,
                g.protocol_config_json,
                g.default_model
            FROM gateways g
            JOIN providers p ON p.id = g.default_provider_id
            WHERE g.id = ?1
            "#,
        )
        .bind(gateway_id)
        .fetch_optional(&self.pool)
        .await?
        .ok_or_else(|| anyhow!("gateway not found: {gateway_id}"))?;

        let configured_protocol = row.get::<String, _>("upstream_protocol");
        let provider_kind = row.get::<String, _>("provider_kind");
        let upstream_protocol = if configured_protocol == "provider_default" {
            provider_kind
        } else {
            configured_protocol
        };
        let protocol_config = serde_json::from_str(&row.get::<String, _>("protocol_config_json"))
            .unwrap_or_else(|_| json!({}));

        Ok(ResolvedTarget {
            provider_id: row.get("provider_id"),
            upstream_protocol,
            base_url: row.get("base_url"),
            api_key: row.get("api_key"),
            effective_model: row.get("default_model"),
            protocol_config,
        })
    }
}
