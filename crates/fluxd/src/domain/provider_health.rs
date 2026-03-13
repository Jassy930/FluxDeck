use serde::{Deserialize, Serialize};

#[derive(Debug, Clone, PartialEq, Eq, Serialize, Deserialize)]
pub struct ProviderHealthState {
    pub provider_id: String,
    pub scope: String,
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
