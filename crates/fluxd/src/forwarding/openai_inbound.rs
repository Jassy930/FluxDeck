use serde_json::Value;

use crate::forwarding::target_resolver::ResolvedTarget;
use crate::forwarding::types::{extract_cached_tokens, ForwardObservation, UsageSnapshot};

pub fn requested_model(payload: &Value) -> Option<String> {
    payload
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}

pub fn stream_requested(payload: &Value) -> bool {
    payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false)
}

pub fn build_observation(
    request_id: &str,
    gateway_id: &str,
    target: &ResolvedTarget,
    requested_model: Option<String>,
    is_stream: bool,
) -> ForwardObservation {
    let mut observation = ForwardObservation::new(request_id, gateway_id);
    observation.provider_id = Some(target.provider_id.clone());
    observation.inbound_protocol = Some("openai".to_string());
    observation.upstream_protocol = Some(target.upstream_protocol.clone());
    observation.model_requested = requested_model.clone();
    observation.model_effective = target.effective_model.clone().or(requested_model);
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

pub fn extract_usage(response: &Value) -> UsageSnapshot {
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

pub fn effective_model(response: &Value) -> Option<String> {
    response
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
}
