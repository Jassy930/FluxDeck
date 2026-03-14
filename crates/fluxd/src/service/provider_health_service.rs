use anyhow::Result;
use sqlx::SqlitePool;
use std::time::{SystemTime, UNIX_EPOCH};

use crate::domain::provider_health::ProviderHealthState;
use crate::repo::provider_health_repo::ProviderHealthRepo;

const FAILURE_THRESHOLD_UNHEALTHY: i64 = 3;
const SUCCESS_THRESHOLD_HEALTHY: i64 = 2;
const BASE_PROBE_BACKOFF_NANOS: u128 = 30_000_000_000;

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

    pub async fn get_scoped_state(
        &self,
        provider_id: &str,
        gateway_id: Option<&str>,
        model: Option<&str>,
    ) -> Result<Option<ProviderHealthState>> {
        self.repo.get_scoped(provider_id, gateway_id, model).await
    }

    pub async fn list_states(&self) -> Result<Vec<ProviderHealthState>> {
        self.repo.list_all().await
    }

    pub async fn states_for_provider(&self, provider_id: &str) -> Result<Vec<ProviderHealthState>> {
        Ok(self
            .repo
            .list_all()
            .await?
            .into_iter()
            .filter(|state| state.provider_id == provider_id)
            .collect())
    }

    pub async fn ensure_provider(&self, provider_id: &str) -> Result<ProviderHealthState> {
        self.repo.ensure_default(provider_id).await
    }

    pub async fn ensure_provider_scope(
        &self,
        provider_id: &str,
        gateway_id: &str,
        model: Option<&str>,
    ) -> Result<ProviderHealthState> {
        self.repo
            .ensure_gateway_scope(provider_id, gateway_id, model)
            .await
    }

    pub async fn delete_provider(&self, provider_id: &str) -> Result<()> {
        self.repo.delete_by_provider_id(provider_id).await
    }

    pub async fn record_failure(
        &self,
        provider_id: &str,
        reason: &str,
    ) -> Result<ProviderHealthState> {
        self.record_failure_inner(provider_id, None, None, reason)
            .await
    }

    pub async fn record_failure_for_gateway(
        &self,
        gateway_id: &str,
        provider_id: &str,
        reason: &str,
    ) -> Result<ProviderHealthState> {
        self.record_failure_inner(provider_id, Some(gateway_id), None, reason)
            .await
    }

    pub async fn mark_probe_result(
        &self,
        provider_id: &str,
        success: bool,
        failure_reason: Option<&str>,
    ) -> Result<ProviderHealthState> {
        self.mark_probe_result_inner(provider_id, None, None, success, failure_reason)
            .await
    }

    pub async fn mark_probe_result_for_gateway(
        &self,
        gateway_id: &str,
        provider_id: &str,
        success: bool,
        failure_reason: Option<&str>,
    ) -> Result<ProviderHealthState> {
        self.mark_probe_result_inner(provider_id, Some(gateway_id), None, success, failure_reason)
            .await
    }

    pub async fn mark_probe_result_for_state(
        &self,
        state: &ProviderHealthState,
        success: bool,
        failure_reason: Option<&str>,
    ) -> Result<ProviderHealthState> {
        self.mark_probe_result_inner(
            &state.provider_id,
            state.gateway_id.as_deref(),
            state.model.as_deref(),
            success,
            failure_reason,
        )
        .await
    }

    pub async fn probe_provider(&self, provider_id: &str) -> Result<ProviderHealthState> {
        let global = self.mark_probe_result(provider_id, true, None).await?;
        for state in self.repo.list_all().await?.into_iter().filter(|state| {
            state.provider_id == provider_id
                && state.gateway_id.is_some()
                && state.status == "unhealthy"
        }) {
            self.mark_probe_result_for_state(&state, true, None).await?;
        }
        Ok(global)
    }

    pub async fn record_success(&self, provider_id: &str) -> Result<ProviderHealthState> {
        self.record_success_inner(provider_id, None, None).await
    }

    pub async fn record_success_for_gateway(
        &self,
        gateway_id: &str,
        provider_id: &str,
    ) -> Result<ProviderHealthState> {
        self.record_success_inner(provider_id, Some(gateway_id), None)
            .await
    }

    async fn record_failure_inner(
        &self,
        provider_id: &str,
        gateway_id: Option<&str>,
        model: Option<&str>,
        reason: &str,
    ) -> Result<ProviderHealthState> {
        let now = now_string();
        let mut state = self.load_or_default(provider_id, gateway_id, model).await?;
        state.failure_streak += 1;
        state.success_streak = 0;
        state.last_check_at = Some(now.clone());
        state.last_failure_at = Some(now.clone());
        state.last_failure_reason = Some(reason.to_string());

        if state.failure_streak >= FAILURE_THRESHOLD_UNHEALTHY {
            state.status = "unhealthy".to_string();
            state.circuit_open_until = Some(now);
            state.recover_after = Some(next_recover_after(state.failure_streak));
        } else {
            state.status = "degraded".to_string();
            state.circuit_open_until = None;
            state.recover_after = None;
        }

        self.repo.upsert(&state).await?;
        Ok(state)
    }

    async fn mark_probe_result_inner(
        &self,
        provider_id: &str,
        gateway_id: Option<&str>,
        model: Option<&str>,
        success: bool,
        failure_reason: Option<&str>,
    ) -> Result<ProviderHealthState> {
        let now = now_string();
        let mut state = self.load_or_default(provider_id, gateway_id, model).await?;
        state.last_check_at = Some(now.clone());

        if success {
            state.status = "probing".to_string();
            state.success_streak = 0;
            state.last_success_at = Some(now);
            state.circuit_open_until = None;
            state.recover_after = None;
        } else {
            state.status = "unhealthy".to_string();
            state.failure_streak = (state.failure_streak + 1).max(FAILURE_THRESHOLD_UNHEALTHY);
            state.success_streak = 0;
            state.last_failure_at = Some(now.clone());
            state.last_failure_reason = failure_reason.map(ToOwned::to_owned);
            state.circuit_open_until = Some(now);
            state.recover_after = Some(next_recover_after(state.failure_streak));
        }

        self.repo.upsert(&state).await?;
        Ok(state)
    }

    async fn record_success_inner(
        &self,
        provider_id: &str,
        gateway_id: Option<&str>,
        model: Option<&str>,
    ) -> Result<ProviderHealthState> {
        let now = now_string();
        let mut state = self.load_or_default(provider_id, gateway_id, model).await?;
        state.failure_streak = 0;
        state.success_streak += 1;
        state.last_check_at = Some(now.clone());
        state.last_success_at = Some(now);

        if state.status == "probing" {
            if state.success_streak >= SUCCESS_THRESHOLD_HEALTHY {
                state.status = "healthy".to_string();
                state.circuit_open_until = None;
                state.recover_after = None;
            }
        } else {
            state.status = "healthy".to_string();
            state.circuit_open_until = None;
            state.recover_after = None;
        }

        self.repo.upsert(&state).await?;
        Ok(state)
    }

    async fn load_or_default(
        &self,
        provider_id: &str,
        gateway_id: Option<&str>,
        model: Option<&str>,
    ) -> Result<ProviderHealthState> {
        let existing = self.repo.get_scoped(provider_id, gateway_id, model).await?;
        Ok(match (existing, gateway_id) {
            (Some(state), _) => state,
            (None, Some(gateway_id)) => {
                ProviderHealthState::gateway(provider_id, gateway_id, model)
            }
            (None, None) => ProviderHealthState::global(provider_id),
        })
    }
}

fn now_string() -> String {
    now_nanos().to_string()
}

fn now_nanos() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}

fn next_recover_after(failure_streak: i64) -> String {
    let exponent = failure_streak
        .saturating_sub(FAILURE_THRESHOLD_UNHEALTHY)
        .clamp(0, 6) as u32;
    let multiplier = 1_u128 << exponent;
    now_nanos()
        .saturating_add(BASE_PROBE_BACKOFF_NANOS.saturating_mul(multiplier))
        .to_string()
}
