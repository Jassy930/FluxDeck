use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::domain::provider_health::ProviderHealthState;

const GLOBAL_SCOPE: &str = "global";
const GATEWAY_SCOPE: &str = "gateway_provider";

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
        self.get_scoped(provider_id, None, None).await
    }

    pub async fn get_scoped(
        &self,
        provider_id: &str,
        gateway_id: Option<&str>,
        model: Option<&str>,
    ) -> Result<Option<ProviderHealthState>> {
        let (scope, gateway_key, model_key) = scope_parts(gateway_id, model);
        let row = sqlx::query(
            r#"
            SELECT
                provider_id,
                scope,
                gateway_id,
                model,
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
              AND scope = ?2
              AND gateway_id = ?3
              AND model = ?4
            "#,
        )
        .bind(provider_id)
        .bind(scope)
        .bind(gateway_key)
        .bind(model_key)
        .fetch_optional(&self.pool)
        .await?;

        Ok(row.map(row_to_state))
    }

    pub async fn upsert(&self, state: &ProviderHealthState) -> Result<()> {
        let scope = normalize_scope(&state.scope, state.gateway_id.as_deref());
        let gateway_key = state.gateway_id.as_deref().unwrap_or("");
        let model_key = state.model.as_deref().unwrap_or("");
        let synthetic_id = scope_record_id(&state.provider_id, &scope, gateway_key, model_key);

        sqlx::query(
            r#"
            INSERT INTO provider_health_states (
                id,
                provider_id,
                scope,
                gateway_id,
                model,
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
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11, ?12, ?13, ?14, CURRENT_TIMESTAMP)
            ON CONFLICT(provider_id, scope, gateway_id, model) DO UPDATE SET
                id = excluded.id,
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
        .bind(synthetic_id)
        .bind(&state.provider_id)
        .bind(scope)
        .bind(gateway_key)
        .bind(model_key)
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
                gateway_id,
                model,
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
            ORDER BY provider_id ASC, scope ASC, gateway_id ASC, model ASC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        Ok(rows.into_iter().map(row_to_state).collect())
    }

    pub async fn ensure_default(&self, provider_id: &str) -> Result<ProviderHealthState> {
        if let Some(existing) = self.get_by_provider_id(provider_id).await? {
            return Ok(existing);
        }

        let state = ProviderHealthState::global(provider_id);
        self.upsert(&state).await?;
        Ok(state)
    }

    pub async fn ensure_gateway_scope(
        &self,
        provider_id: &str,
        gateway_id: &str,
        model: Option<&str>,
    ) -> Result<ProviderHealthState> {
        if let Some(existing) = self.get_scoped(provider_id, Some(gateway_id), model).await? {
            return Ok(existing);
        }

        let state = ProviderHealthState::gateway(provider_id, gateway_id, model);
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

fn row_to_state(row: sqlx::sqlite::SqliteRow) -> ProviderHealthState {
    ProviderHealthState {
        provider_id: row.get("provider_id"),
        scope: row.get("scope"),
        gateway_id: normalize_optional(row.get::<String, _>("gateway_id")),
        model: normalize_optional(row.get::<String, _>("model")),
        status: row.get("status"),
        failure_streak: row.get("failure_streak"),
        success_streak: row.get("success_streak"),
        last_check_at: row.get("last_check_at"),
        last_success_at: row.get("last_success_at"),
        last_failure_at: row.get("last_failure_at"),
        last_failure_reason: row.get("last_failure_reason"),
        circuit_open_until: row.get("circuit_open_until"),
        recover_after: row.get("recover_after"),
    }
}

fn normalize_scope(scope: &str, gateway_id: Option<&str>) -> String {
    if gateway_id.is_some() && scope == GLOBAL_SCOPE {
        return GATEWAY_SCOPE.to_string();
    }
    scope.to_string()
}

fn scope_parts<'a>(gateway_id: Option<&'a str>, model: Option<&'a str>) -> (&'static str, &'a str, &'a str) {
    match gateway_id {
        Some(gateway_id) => (GATEWAY_SCOPE, gateway_id, model.unwrap_or("")),
        None => (GLOBAL_SCOPE, "", ""),
    }
}

fn scope_record_id(provider_id: &str, scope: &str, gateway_id: &str, model: &str) -> String {
    if gateway_id.is_empty() && model.is_empty() {
        return format!("{provider_id}:{scope}");
    }
    format!("{provider_id}:{scope}:{gateway_id}:{model}")
}

fn normalize_optional(value: String) -> Option<String> {
    if value.is_empty() {
        None
    } else {
        Some(value)
    }
}
