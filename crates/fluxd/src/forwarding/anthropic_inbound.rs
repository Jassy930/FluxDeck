use serde_json::Value;

use crate::forwarding::types::{extract_cached_tokens, ForwardObservation, UsageSnapshot};

pub fn build_observation(
    request_id: &str,
    gateway_id: &str,
    provider_id: &str,
    upstream_protocol: &str,
    requested_model: Option<String>,
    effective_model: Option<String>,
    is_stream: bool,
) -> ForwardObservation {
    let mut observation = ForwardObservation::new(request_id, gateway_id);
    observation.provider_id = Some(provider_id.to_string());
    observation.inbound_protocol = Some("anthropic".to_string());
    observation.upstream_protocol = Some(upstream_protocol.to_string());
    observation.model_requested = requested_model;
    observation.model_effective = effective_model;
    observation.is_stream = is_stream;
    observation
}

pub fn apply_response(
    observation: &mut ForwardObservation,
    status_code: i64,
    latency_ms: i64,
    first_byte_ms: i64,
    effective_model: Option<String>,
) {
    observation.status_code = Some(status_code);
    observation.latency_ms = Some(latency_ms);
    observation.first_byte_ms = Some(first_byte_ms);
    if effective_model.is_some() {
        observation.model_effective = effective_model;
    }
}

pub fn extract_openai_usage(response: &Value) -> UsageSnapshot {
    let usage = response.get("usage").and_then(Value::as_object);
    let input_tokens = usage
        .and_then(|item| item.get("prompt_tokens"))
        .and_then(Value::as_i64);
    let output_tokens = usage
        .and_then(|item| item.get("completion_tokens"))
        .and_then(Value::as_i64);
    let cached_tokens = extract_cached_tokens(usage);
    let total_tokens = usage
        .and_then(|item| item.get("total_tokens"))
        .and_then(Value::as_i64)
        .or_else(|| match (input_tokens, output_tokens) {
            (Some(input), Some(output)) => Some(input + output),
            _ => None,
        });

    UsageSnapshot {
        input_tokens,
        output_tokens,
        cached_tokens,
        total_tokens,
        usage_json: usage.map(|_| response["usage"].clone()),
    }
}

pub fn extract_anthropic_usage(response: &Value) -> UsageSnapshot {
    let usage = response.get("usage").and_then(Value::as_object);
    let input_tokens = usage
        .and_then(|item| item.get("input_tokens"))
        .and_then(Value::as_i64);
    let output_tokens = usage
        .and_then(|item| item.get("output_tokens"))
        .and_then(Value::as_i64);
    let cached_tokens = extract_cached_tokens(usage);
    let total_tokens = match (input_tokens, output_tokens) {
        (Some(input), Some(output)) => Some(input + output),
        _ => None,
    };

    UsageSnapshot {
        input_tokens,
        output_tokens,
        cached_tokens,
        total_tokens,
        usage_json: usage.map(|_| response["usage"].clone()),
    }
}

pub fn usage_from_input_tokens(input_tokens: i64) -> UsageSnapshot {
    UsageSnapshot {
        input_tokens: Some(input_tokens),
        output_tokens: None,
        cached_tokens: None,
        total_tokens: Some(input_tokens),
        usage_json: Some(serde_json::json!({ "input_tokens": input_tokens })),
    }
}
