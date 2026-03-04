use anyhow::Result;
use serde_json::Value;
use sqlx::SqlitePool;

#[derive(Debug, Clone)]
pub struct RequestLogEntry {
    pub request_id: String,
    pub gateway_id: String,
    pub provider_id: String,
    pub model: Option<String>,
    pub status_code: i64,
    pub latency_ms: i64,
    pub error: Option<String>,
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
        if dimensions.as_object().is_some_and(|item| !item.is_empty()) {
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

        sqlx::query(
            r#"
            INSERT INTO request_logs (
                request_id, gateway_id, provider_id, model, status_code, latency_ms, error
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7)
            "#,
        )
        .bind(&entry.request_id)
        .bind(&entry.gateway_id)
        .bind(&entry.provider_id)
        .bind(&entry.model)
        .bind(entry.status_code)
        .bind(entry.latency_ms)
        .bind(&entry.error)
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
}
