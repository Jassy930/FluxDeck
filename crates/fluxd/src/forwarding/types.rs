#[derive(Debug, Clone, Default)]
pub struct ForwardObservation {
    pub request_id: String,
    pub gateway_id: String,
    pub provider_id: Option<String>,
    pub provider_id_initial: Option<String>,
    pub inbound_protocol: Option<String>,
    pub upstream_protocol: Option<String>,
    pub model_requested: Option<String>,
    pub model_effective: Option<String>,
    pub is_stream: bool,
    pub failover_performed: bool,
    pub route_attempt_count: i64,
    pub status_code: Option<i64>,
    pub latency_ms: Option<i64>,
    pub first_byte_ms: Option<i64>,
    pub error_stage: Option<String>,
    pub error_type: Option<String>,
}

impl ForwardObservation {
    pub fn new(request_id: impl Into<String>, gateway_id: impl Into<String>) -> Self {
        Self {
            request_id: request_id.into(),
            gateway_id: gateway_id.into(),
            provider_id: None,
            provider_id_initial: None,
            inbound_protocol: None,
            upstream_protocol: None,
            model_requested: None,
            model_effective: None,
            is_stream: false,
            failover_performed: false,
            route_attempt_count: 0,
            status_code: None,
            latency_ms: None,
            first_byte_ms: None,
            error_stage: None,
            error_type: None,
        }
    }

    pub fn apply_route_attempts(
        &mut self,
        provider_id_initial: Option<String>,
        route_attempt_count: usize,
    ) {
        self.provider_id_initial = provider_id_initial;
        self.route_attempt_count = route_attempt_count as i64;
        self.failover_performed = route_attempt_count > 1;
    }
}

#[derive(Debug, Clone, Default)]
pub struct UsageSnapshot {
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub cached_tokens: Option<i64>,
    pub total_tokens: Option<i64>,
    pub usage_json: Option<serde_json::Value>,
}

pub fn extract_cached_tokens(
    usage: Option<&serde_json::Map<String, serde_json::Value>>,
) -> Option<i64> {
    let usage = usage?;

    usage
        .get("cached_tokens")
        .and_then(serde_json::Value::as_i64)
        .or_else(|| {
            usage
                .get("cache_read_input_tokens")
                .and_then(serde_json::Value::as_i64)
        })
        .or_else(|| {
            usage
                .get("cache_read_tokens")
                .and_then(serde_json::Value::as_i64)
        })
        .or_else(|| {
            usage
                .get("prompt_tokens_details")
                .and_then(serde_json::Value::as_object)
                .and_then(|details| details.get("cached_tokens"))
                .and_then(serde_json::Value::as_i64)
        })
        .or_else(|| {
            usage
                .get("input_tokens_details")
                .and_then(serde_json::Value::as_object)
                .and_then(|details| details.get("cached_tokens"))
                .and_then(serde_json::Value::as_i64)
        })
}
