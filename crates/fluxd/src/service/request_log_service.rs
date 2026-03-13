use anyhow::Result;
use serde_json::Value;
use sqlx::SqlitePool;

use crate::forwarding::types::{ForwardObservation, UsageSnapshot};

#[derive(Debug, Clone)]
pub struct RequestLogEntry {
    pub request_id: String,
    pub gateway_id: String,
    pub provider_id: String,
    pub model: Option<String>,
    pub status_code: i64,
    pub latency_ms: i64,
    pub error: Option<String>,
    pub observation: ForwardObservation,
    pub usage: UsageSnapshot,
}

#[derive(Clone)]
pub struct RequestLogService {
    pool: SqlitePool,
}

impl RequestLogService {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn append_and_trim_with_dimensions(
        &self,
        mut entry: RequestLogEntry,
        keep: i64,
        dimensions: &Value,
    ) -> Result<()> {
        let should_attach_dimensions = dimensions.as_object().is_some_and(|item| !item.is_empty())
            && (entry.status_code >= 400 || entry.error.is_some());
        if should_attach_dimensions {
            let dimensions_text = format!("dimensions={dimensions}");
            entry.error = Some(match entry.error.take() {
                Some(error) => format!("{error} | {dimensions_text}"),
                None => dimensions_text,
            });
        }

        self.append_and_trim(entry, keep).await
    }

    pub async fn append_and_trim(&self, entry: RequestLogEntry, keep: i64) -> Result<()> {
        let mut tx = self.pool.begin().await?;
        let provider_id_initial = entry
            .observation
            .provider_id_initial
            .clone()
            .or_else(|| entry.observation.provider_id.clone())
            .or_else(|| (entry.provider_id != "unknown").then_some(entry.provider_id.clone()));
        let route_attempt_count = if entry.observation.route_attempt_count > 0 {
            entry.observation.route_attempt_count
        } else if provider_id_initial.is_some() {
            1
        } else {
            0
        };
        let failover_performed = entry.observation.failover_performed || route_attempt_count > 1;

        sqlx::query(
            r#"
            INSERT INTO request_logs (
                request_id, gateway_id, provider_id, model, status_code, latency_ms, error,
                inbound_protocol, upstream_protocol, model_requested, model_effective,
                stream, first_byte_ms, input_tokens, output_tokens, cached_tokens,
                total_tokens, usage_json, error_stage, error_type,
                failover_performed, route_attempt_count, provider_id_initial
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, ?15, ?16, ?17, ?18, ?19, ?20, ?21, ?22, ?23)
            "#,
        )
        .bind(&entry.request_id)
        .bind(&entry.gateway_id)
        .bind(&entry.provider_id)
        .bind(&entry.model)
        .bind(entry.status_code)
        .bind(entry.latency_ms)
        .bind(&entry.error)
        .bind(&entry.observation.inbound_protocol)
        .bind(&entry.observation.upstream_protocol)
        .bind(&entry.observation.model_requested)
        .bind(&entry.observation.model_effective)
        .bind(if entry.observation.is_stream { 1_i64 } else { 0_i64 })
        .bind(entry.observation.first_byte_ms)
        .bind(entry.usage.input_tokens)
        .bind(entry.usage.output_tokens)
        .bind(entry.usage.cached_tokens)
        .bind(entry.usage.total_tokens)
        .bind(entry.usage.usage_json.as_ref().map(Value::to_string))
        .bind(&entry.observation.error_stage)
        .bind(&entry.observation.error_type)
        .bind(if failover_performed { 1_i64 } else { 0_i64 })
        .bind(route_attempt_count)
        .bind(provider_id_initial)
        .execute(&mut *tx)
        .await?;

        sqlx::query(
            r#"
            DELETE FROM request_logs
            WHERE rowid IN (
                SELECT rowid
                FROM request_logs
                ORDER BY rowid DESC
                LIMIT -1 OFFSET ?1
            )
            "#,
        )
        .bind(keep)
        .execute(&mut *tx)
        .await?;

        tx.commit().await?;
        Ok(())
    }

    pub async fn update_usage(&self, request_id: &str, usage: &UsageSnapshot) -> Result<()> {
        sqlx::query(
            r#"
            UPDATE request_logs
            SET input_tokens = ?2,
                output_tokens = ?3,
                cached_tokens = ?4,
                total_tokens = ?5,
                usage_json = ?6
            WHERE request_id = ?1
            "#,
        )
        .bind(request_id)
        .bind(usage.input_tokens)
        .bind(usage.output_tokens)
        .bind(usage.cached_tokens)
        .bind(usage.total_tokens)
        .bind(usage.usage_json.as_ref().map(Value::to_string))
        .execute(&self.pool)
        .await?;

        Ok(())
    }
}
