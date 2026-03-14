use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderHealthState {
    pub provider_id: String,
    pub scope: String,
    pub gateway_id: Option<String>,
    pub model: Option<String>,
    pub status: String,
    pub failure_streak: i64,
    pub success_streak: i64,
    pub last_check_at: Option<String>,
    pub last_success_at: Option<String>,
    pub last_failure_at: Option<String>,
    pub last_failure_reason: Option<String>,
    pub circuit_open_until: Option<String>,
    pub recover_after: Option<String>,
}

impl ProviderHealthState {
    pub fn global(provider_id: &str) -> Self {
        Self {
            provider_id: provider_id.to_string(),
            scope: "global".to_string(),
            gateway_id: None,
            model: None,
            status: "healthy".to_string(),
            failure_streak: 0,
            success_streak: 0,
            last_check_at: None,
            last_success_at: None,
            last_failure_at: None,
            last_failure_reason: None,
            circuit_open_until: None,
            recover_after: None,
        }
    }

    pub fn gateway(provider_id: &str, gateway_id: &str, model: Option<&str>) -> Self {
        Self {
            provider_id: provider_id.to_string(),
            scope: "gateway_provider".to_string(),
            gateway_id: Some(gateway_id.to_string()),
            model: model.map(ToOwned::to_owned),
            ..Self::global(provider_id)
        }
    }
}
