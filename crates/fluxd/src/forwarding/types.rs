#[derive(Debug, Clone, Default)]
pub struct ForwardObservation {
    pub request_id: String,
    pub gateway_id: String,
    pub provider_id: Option<String>,
    pub inbound_protocol: Option<String>,
    pub upstream_protocol: Option<String>,
    pub model_requested: Option<String>,
    pub model_effective: Option<String>,
    pub is_stream: bool,
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
            inbound_protocol: None,
            upstream_protocol: None,
            model_requested: None,
            model_effective: None,
            is_stream: false,
            status_code: None,
            latency_ms: None,
            first_byte_ms: None,
            error_stage: None,
            error_type: None,
        }
    }
}

#[derive(Debug, Clone, Default)]
pub struct UsageSnapshot {
    pub input_tokens: Option<i64>,
    pub output_tokens: Option<i64>,
    pub total_tokens: Option<i64>,
    pub usage_json: Option<serde_json::Value>,
}
