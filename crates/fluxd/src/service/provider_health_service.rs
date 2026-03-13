use anyhow::Result;
use sqlx::SqlitePool;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::domain::provider_health::ProviderHealthState;
use crate::repo::provider_health_repo::ProviderHealthRepo;

const FAILURE_THRESHOLD_UNHEALTHY: i64 = 3;
const SUCCESS_THRESHOLD_HEALTHY: i64 = 2;

#[derive(Clone)]
pub struct ProviderHealthService {
    repo: ProviderHealthRepo,
}

impl ProviderHealthService {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: ProviderHealthRepo::new(pool),
        }
    }

    pub async fn get_state(&self, provider_id: &str) -> Result<Option<ProviderHealthState>> {
        self.repo.get_by_provider_id(provider_id).await
    }

    pub async fn list_states(&self) -> Result<Vec<ProviderHealthState>> {
        self.repo.list_all().await
    }

    pub async fn ensure_provider(&self, provider_id: &str) -> Result<ProviderHealthState> {
        self.repo.ensure_default(provider_id).await
    }

    pub async fn delete_provider(&self, provider_id: &str) -> Result<()> {
        self.repo.delete_by_provider_id(provider_id).await
    }

    pub async fn record_failure(
        &self,
        provider_id: &str,
        reason: &str,
    ) -> Result<ProviderHealthState> {
        let now = now_string();
        let mut state = self.load_or_default(provider_id).await?;
        state.failure_streak += 1;
        state.success_streak = 0;
        state.last_check_at = Some(now.clone());
        state.last_failure_at = Some(now.clone());
        state.last_failure_reason = Some(reason.to_string());

        if state.failure_streak >= FAILURE_THRESHOLD_UNHEALTHY {
            state.status = "unhealthy".to_string();
            state.circuit_open_until = Some(now.clone());
            state.recover_after = Some(now);
        } else {
            state.status = "degraded".to_string();
        }

        self.repo.upsert(&state).await?;
        Ok(state)
    }

    pub async fn mark_probe_result(
        &self,
        provider_id: &str,
        success: bool,
        failure_reason: Option<&str>,
    ) -> Result<ProviderHealthState> {
        let now = now_string();
        let mut state = self.load_or_default(provider_id).await?;
        state.last_check_at = Some(now.clone());

        if success {
            state.status = "probing".to_string();
            state.success_streak = 0;
            state.last_success_at = Some(now.clone());
        } else {
            state.status = "unhealthy".to_string();
            state.last_failure_at = Some(now.clone());
            state.last_failure_reason = failure_reason.map(ToOwned::to_owned);
            state.circuit_open_until = Some(now.clone());
            state.recover_after = Some(now.clone());
        }

        self.repo.upsert(&state).await?;
        Ok(state)
    }

    pub async fn probe_provider(&self, provider_id: &str) -> Result<ProviderHealthState> {
        self.mark_probe_result(provider_id, true, None).await
    }

    pub async fn record_success(&self, provider_id: &str) -> Result<ProviderHealthState> {
        let now = now_string();
        let mut state = self.load_or_default(provider_id).await?;
        state.failure_streak = 0;
        state.success_streak += 1;
        state.last_check_at = Some(now.clone());
        state.last_success_at = Some(now);

        if state.status == "probing" && state.success_streak >= SUCCESS_THRESHOLD_HEALTHY {
            state.status = "healthy".to_string();
            state.circuit_open_until = None;
        } else if state.status != "probing" {
            state.status = "healthy".to_string();
            state.circuit_open_until = None;
        }

        self.repo.upsert(&state).await?;
        Ok(state)
    }

    async fn load_or_default(&self, provider_id: &str) -> Result<ProviderHealthState> {
        Ok(self
            .repo
            .get_by_provider_id(provider_id)
            .await?
            .unwrap_or_else(|| ProviderHealthState {
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
            }))
    }
}

fn now_string() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0);
    format!("{nanos}")
}
