use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::domain::provider_health::ProviderHealthState;

#[derive(Clone)]
pub struct ProviderHealthRepo {
    pool: SqlitePool,
}

impl ProviderHealthRepo {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn get_by_provider_id(
        &self,
        provider_id: &str,
    ) -> Result<Option<ProviderHealthState>> {
        let row = sqlx::query(
            r#"
            SELECT
                provider_id,
                scope,
                status,
                failure_streak,
                success_streak,
                last_check_at,
                last_success_at,
                last_failure_at,
                last_failure_reason,
                circuit_open_until,
                recover_after
            FROM provider_health_states
            WHERE provider_id = ?1
            "#,
        )
        .bind(provider_id)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(|row| ProviderHealthState {
            provider_id: row.get("provider_id"),
            scope: row.get("scope"),
            status: row.get("status"),
            failure_streak: row.get("failure_streak"),
            success_streak: row.get("success_streak"),
            last_check_at: row.get("last_check_at"),
            last_success_at: row.get("last_success_at"),
            last_failure_at: row.get("last_failure_at"),
            last_failure_reason: row.get("last_failure_reason"),
            circuit_open_until: row.get("circuit_open_until"),
            recover_after: row.get("recover_after"),
        }))
    }

    pub async fn upsert(&self, state: &ProviderHealthState) -> Result<()> {
        sqlx::query(
            r#"
            INSERT INTO provider_health_states (
                provider_id,
                scope,
                status,
                failure_streak,
                success_streak,
                last_check_at,
                last_success_at,
                last_failure_at,
                last_failure_reason,
                circuit_open_until,
                recover_after,
                updated_at
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, CURRENT_TIMESTAMP)
            ON CONFLICT(provider_id) DO UPDATE SET
                scope = excluded.scope,
                status = excluded.status,
                failure_streak = excluded.failure_streak,
                success_streak = excluded.success_streak,
                last_check_at = excluded.last_check_at,
                last_success_at = excluded.last_success_at,
                last_failure_at = excluded.last_failure_at,
                last_failure_reason = excluded.last_failure_reason,
                circuit_open_until = excluded.circuit_open_until,
                recover_after = excluded.recover_after,
                updated_at = CURRENT_TIMESTAMP
            "#,
        )
        .bind(&state.provider_id)
        .bind(&state.scope)
        .bind(&state.status)
        .bind(state.failure_streak)
        .bind(state.success_streak)
        .bind(&state.last_check_at)
        .bind(&state.last_success_at)
        .bind(&state.last_failure_at)
        .bind(&state.last_failure_reason)
        .bind(&state.circuit_open_until)
        .bind(&state.recover_after)
        .execute(&self.pool)
        .await?;

        Ok(())
    }

    pub async fn list_all(&self) -> Result<Vec<ProviderHealthState>> {
        let rows = sqlx::query(
            r#"
            SELECT
                provider_id,
                scope,
                status,
                failure_streak,
                success_streak,
                last_check_at,
                last_success_at,
                last_failure_at,
                last_failure_reason,
                circuit_open_until,
                recover_after
            FROM provider_health_states
            ORDER BY provider_id ASC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| ProviderHealthState {
                provider_id: row.get("provider_id"),
                scope: row.get("scope"),
                status: row.get("status"),
                failure_streak: row.get("failure_streak"),
                success_streak: row.get("success_streak"),
                last_check_at: row.get("last_check_at"),
                last_success_at: row.get("last_success_at"),
                last_failure_at: row.get("last_failure_at"),
                last_failure_reason: row.get("last_failure_reason"),
                circuit_open_until: row.get("circuit_open_until"),
                recover_after: row.get("recover_after"),
            })
            .collect())
    }

    pub async fn ensure_default(&self, provider_id: &str) -> Result<ProviderHealthState> {
        if let Some(existing) = self.get_by_provider_id(provider_id).await? {
            return Ok(existing);
        }

        let state = ProviderHealthState {
            provider_id: provider_id.to_string(),
            scope: "global".to_string(),
            status: "healthy".to_string(),
            failure_streak: 0,
            success_streak: 0,
            last_check_at: None,
            last_success_at: None,
            last_failure_at: None,
            last_failure_reason: None,
            circuit_open_until: None,
            recover_after: None,
        };
        self.upsert(&state).await?;
        Ok(state)
    }

    pub async fn delete_by_provider_id(&self, provider_id: &str) -> Result<()> {
        sqlx::query("DELETE FROM provider_health_states WHERE provider_id = ?1")
            .bind(provider_id)
            .execute(&self.pool)
            .await?;
        Ok(())
    }
}
