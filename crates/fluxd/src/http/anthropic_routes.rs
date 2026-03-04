use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    extract::{Json, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Router,
};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

use crate::protocol::adapters::anthropic::{decode_anthropic_request, encode_anthropic_sse};
use crate::protocol::adapters::openai::{decode_openai_sse_events, encode_openai_chat_request};
use crate::service::request_log_service::{RequestLogEntry, RequestLogService};
use crate::upstream::openai_client::OpenAiClient;

const REQUEST_LOG_KEEP: i64 = 10_000;

#[derive(Clone)]
pub struct AnthropicRouteState {
    pool: SqlitePool,
    gateway_id: String,
    client: OpenAiClient,
}

impl AnthropicRouteState {
    pub fn new(pool: SqlitePool, gateway_id: impl Into<String>) -> Self {
        Self {
            pool,
            gateway_id: gateway_id.into(),
            client: OpenAiClient::new(),
        }
    }
}

pub fn build_anthropic_router(state: AnthropicRouteState) -> Router {
    Router::new()
        .route("/v1/messages", post(forward_messages))
        .with_state(state)
}

async fn forward_messages(
    State(state): State<AnthropicRouteState>,
    Json(payload): Json<Value>,
) -> Response {
    let request_id = next_request_id();
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let stream_requested = payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let started_at = Instant::now();
    let log_service = RequestLogService::new(state.pool.clone());

    let ir = match decode_anthropic_request(&payload) {
        Ok(ir) => ir,
        Err(err) => {
            append_log(
                &log_service,
                RequestLogEntry {
                    request_id,
                    gateway_id: state.gateway_id.clone(),
                    provider_id: "unknown".to_string(),
                    model,
                    status_code: i64::from(StatusCode::BAD_REQUEST.as_u16()),
                    latency_ms: started_at.elapsed().as_millis() as i64,
                    error: Some(err.to_string()),
                },
            )
            .await;

            return (
                StatusCode::BAD_REQUEST,
                Json(anthropic_error_response(
                    format!("invalid request: {err}"),
                    "invalid_request_error",
                )),
            )
                .into_response();
        }
    };

    match fetch_provider_target(&state).await {
        Ok(target) => {
            let mut upstream_payload = match encode_openai_chat_request(&ir) {
                Ok(payload) => payload,
                Err(err) => {
                    append_log(
                        &log_service,
                        RequestLogEntry {
                            request_id,
                            gateway_id: state.gateway_id.clone(),
                            provider_id: target.provider_id,
                            model,
                            status_code: i64::from(StatusCode::BAD_REQUEST.as_u16()),
                            latency_ms: started_at.elapsed().as_millis() as i64,
                            error: Some(err.to_string()),
                        },
                    )
                    .await;

                    return (
                        StatusCode::BAD_REQUEST,
                        Json(anthropic_error_response(
                            format!("invalid request: {err}"),
                            "invalid_request_error",
                        )),
                    )
                        .into_response();
                }
            };

            if stream_requested {
                if let Some(object) = upstream_payload.as_object_mut() {
                    object.insert("stream".to_string(), Value::Bool(true));
                }

                let response = state
                    .client
                    .chat_completions_stream(&target.base_url, &target.api_key, &upstream_payload)
                    .await;

                match response {
                    Ok((status, raw_sse)) => {
                        let status_code = StatusCode::from_u16(status.as_u16())
                            .unwrap_or(StatusCode::BAD_GATEWAY);

                        if status_code.is_success() {
                            let events = match decode_openai_sse_events(&raw_sse) {
                                Ok(events) => events,
                                Err(err) => {
                                    append_log(
                                        &log_service,
                                        RequestLogEntry {
                                            request_id,
                                            gateway_id: state.gateway_id.clone(),
                                            provider_id: target.provider_id,
                                            model,
                                            status_code: i64::from(StatusCode::BAD_GATEWAY.as_u16()),
                                            latency_ms: started_at.elapsed().as_millis() as i64,
                                            error: Some(err.to_string()),
                                        },
                                    )
                                    .await;

                                    return (
                                        StatusCode::BAD_GATEWAY,
                                        Json(anthropic_error_response(
                                            format!("upstream stream decode failed: {err}"),
                                            "api_error",
                                        )),
                                    )
                                        .into_response();
                                }
                            };

                            append_log(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id,
                                    model,
                                    status_code: i64::from(status_code.as_u16()),
                                    latency_ms: started_at.elapsed().as_millis() as i64,
                                    error: None,
                                },
                            )
                            .await;

                            let anthropic_sse = encode_anthropic_sse(&events);
                            return (
                                status_code,
                                [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
                                anthropic_sse,
                            )
                                .into_response();
                        }

                        append_log(
                            &log_service,
                            RequestLogEntry {
                                request_id: request_id.clone(),
                                gateway_id: state.gateway_id.clone(),
                                provider_id: target.provider_id,
                                model,
                                status_code: i64::from(status_code.as_u16()),
                                latency_ms: started_at.elapsed().as_millis() as i64,
                                error: None,
                            },
                        )
                        .await;

                        let message = extract_upstream_error_message_from_text(&raw_sse);

                        (
                            status_code,
                            Json(anthropic_error_response(message, "api_error")),
                        )
                            .into_response()
                    }
                    Err(err) => {
                        append_log(
                            &log_service,
                            RequestLogEntry {
                                request_id,
                                gateway_id: state.gateway_id.clone(),
                                provider_id: target.provider_id,
                                model,
                                status_code: i64::from(StatusCode::BAD_GATEWAY.as_u16()),
                                latency_ms: started_at.elapsed().as_millis() as i64,
                                error: Some(err.to_string()),
                            },
                        )
                        .await;

                        (
                            StatusCode::BAD_GATEWAY,
                            Json(anthropic_error_response(
                                format!("upstream forward failed: {err}"),
                                "api_error",
                            )),
                        )
                            .into_response()
                    }
                }
            } else {
                let response = state
                    .client
                    .chat_completions(&target.base_url, &target.api_key, &upstream_payload)
                    .await;

                match response {
                    Ok((status, value)) => {
                        let status_code = StatusCode::from_u16(status.as_u16())
                            .unwrap_or(StatusCode::BAD_GATEWAY);

                        append_log(
                            &log_service,
                            RequestLogEntry {
                                request_id: request_id.clone(),
                                gateway_id: state.gateway_id.clone(),
                                provider_id: target.provider_id,
                                model,
                                status_code: i64::from(status_code.as_u16()),
                                latency_ms: started_at.elapsed().as_millis() as i64,
                                error: None,
                            },
                        )
                        .await;

                        if status_code.is_success() {
                            return (status_code, Json(map_openai_to_anthropic_message(&value, &ir)))
                                .into_response();
                        }

                        let message = value
                            .get("error")
                            .and_then(|item| item.get("message"))
                            .and_then(Value::as_str)
                            .unwrap_or("upstream returned an error")
                            .to_string();

                        (
                            status_code,
                            Json(anthropic_error_response(message, "api_error")),
                        )
                            .into_response()
                    }
                    Err(err) => {
                        append_log(
                            &log_service,
                            RequestLogEntry {
                                request_id,
                                gateway_id: state.gateway_id.clone(),
                                provider_id: target.provider_id,
                                model,
                                status_code: i64::from(StatusCode::BAD_GATEWAY.as_u16()),
                                latency_ms: started_at.elapsed().as_millis() as i64,
                                error: Some(err.to_string()),
                            },
                        )
                        .await;

                        (
                            StatusCode::BAD_GATEWAY,
                            Json(anthropic_error_response(
                                format!("upstream forward failed: {err}"),
                                "api_error",
                            )),
                        )
                            .into_response()
                    }
                }
            }
        }
        Err(err) => {
            append_log(
                &log_service,
                RequestLogEntry {
                    request_id,
                    gateway_id: state.gateway_id.clone(),
                    provider_id: "unknown".to_string(),
                    model,
                    status_code: i64::from(StatusCode::BAD_REQUEST.as_u16()),
                    latency_ms: started_at.elapsed().as_millis() as i64,
                    error: Some(err.to_string()),
                },
            )
            .await;

            (
                StatusCode::BAD_REQUEST,
                Json(anthropic_error_response(
                    format!("invalid gateway/provider state: {err}"),
                    "invalid_request_error",
                )),
            )
                .into_response()
        }
    }
}

fn extract_upstream_error_message_from_text(body: &str) -> String {
    if let Ok(value) = serde_json::from_str::<Value>(body) {
        if let Some(message) = value
            .get("error")
            .and_then(|item| item.get("message"))
            .and_then(Value::as_str)
        {
            return message.to_string();
        }
    }

    let trimmed = body.trim();
    if trimmed.is_empty() {
        "upstream returned an error".to_string()
    } else {
        trimmed.to_string()
    }
}

#[derive(Debug)]
struct ProviderRoutingTarget {
    provider_id: String,
    base_url: String,
    api_key: String,
}

async fn fetch_provider_target(
    state: &AnthropicRouteState,
) -> anyhow::Result<ProviderRoutingTarget> {
    let row = sqlx::query(
        r#"
        SELECT p.id AS provider_id, p.base_url, p.api_key
        FROM gateways g
        JOIN providers p ON p.id = g.default_provider_id
        WHERE g.id = ?1
        "#,
    )
    .bind(&state.gateway_id)
    .fetch_optional(&state.pool)
    .await?;

    let row = row.ok_or_else(|| anyhow::anyhow!("gateway not found: {}", state.gateway_id))?;

    Ok(ProviderRoutingTarget {
        provider_id: row.get("provider_id"),
        base_url: row.get("base_url"),
        api_key: row.get("api_key"),
    })
}

fn map_openai_to_anthropic_message(openai_response: &Value, ir: &crate::protocol::ir::IrRequest) -> Value {
    let openai_id = openai_response
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let anthropic_id = if openai_id.starts_with("msg_") {
        openai_id.to_string()
    } else {
        format!("msg_{openai_id}")
    };

    let first_choice = openai_response
        .get("choices")
        .and_then(Value::as_array)
        .and_then(|choices| choices.first());

    let finish_reason = first_choice
        .and_then(|choice| choice.get("finish_reason"))
        .and_then(Value::as_str);

    let first_message = first_choice.and_then(|choice| choice.get("message"));

    let message_content = first_message
        .and_then(|message| message.get("content"))
        .cloned()
        .unwrap_or(Value::Null);

    let mut content = map_content_to_anthropic_blocks(&message_content);
    content.extend(map_tool_calls_to_anthropic_blocks(
        first_message.and_then(|message| message.get("tool_calls")),
    ));
    let has_tool_use_block = content
        .iter()
        .any(|block| block.get("type").and_then(Value::as_str) == Some("tool_use"));

    let usage = openai_response.get("usage").and_then(Value::as_object);
    let input_tokens = usage
        .and_then(|item| item.get("prompt_tokens"))
        .cloned()
        .unwrap_or_else(|| json!(0));
    let output_tokens = usage
        .and_then(|item| item.get("completion_tokens"))
        .cloned()
        .unwrap_or_else(|| json!(0));

    let model = openai_response
        .get("model")
        .cloned()
        .or_else(|| ir.model.as_ref().map(|item| json!(item)))
        .unwrap_or(Value::Null);

    json!({
        "id": anthropic_id,
        "type": "message",
        "role": "assistant",
        "model": model,
        "content": content,
        "stop_reason": map_finish_reason(finish_reason, has_tool_use_block),
        "stop_sequence": Value::Null,
        "usage": {
            "input_tokens": input_tokens,
            "output_tokens": output_tokens
        }
    })
}

fn map_content_to_anthropic_blocks(content: &Value) -> Vec<Value> {
    match content {
        Value::String(text) => vec![json!({
            "type": "text",
            "text": text
        })],
        Value::Array(items) => items.iter().filter_map(map_openai_content_item).collect(),
        Value::Null => Vec::new(),
        other => vec![json!({
            "type": "text",
            "text": stringify_value(other)
        })],
    }
}

fn map_openai_content_item(item: &Value) -> Option<Value> {
    match item {
        Value::String(text) => Some(json!({
            "type": "text",
            "text": text
        })),
        Value::Object(object) => {
            let text = object
                .get("text")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
                .or_else(|| Some(stringify_value(item)))?;

            Some(json!({
                "type": "text",
                "text": text
            }))
        }
        Value::Null => None,
        other => Some(json!({
            "type": "text",
            "text": stringify_value(other)
        })),
    }
}

fn map_tool_calls_to_anthropic_blocks(tool_calls: Option<&Value>) -> Vec<Value> {
    match tool_calls {
        Some(Value::Array(items)) => items.iter().filter_map(map_openai_tool_call_item).collect(),
        _ => Vec::new(),
    }
}

fn map_openai_tool_call_item(item: &Value) -> Option<Value> {
    let object = item.as_object()?;
    let name = object
        .get("function")
        .and_then(Value::as_object)
        .and_then(|function| function.get("name"))
        .and_then(Value::as_str)?;
    let id = object
        .get("id")
        .and_then(Value::as_str)
        .unwrap_or("toolu_unknown");

    let input = object
        .get("function")
        .and_then(Value::as_object)
        .and_then(|function| function.get("arguments"))
        .map(parse_openai_tool_arguments)
        .unwrap_or_else(|| json!({}));

    Some(json!({
        "type": "tool_use",
        "id": id,
        "name": name,
        "input": input
    }))
}

fn parse_openai_tool_arguments(arguments: &Value) -> Value {
    match arguments {
        Value::String(raw) => match serde_json::from_str::<Value>(raw) {
            Ok(object @ Value::Object(_)) => object,
            Ok(other) => json!({ "_value": other }),
            Err(_) => json!({ "_raw": raw }),
        },
        Value::Object(_) => arguments.clone(),
        Value::Null => json!({}),
        other => json!({ "_value": other }),
    }
}

fn map_finish_reason(finish_reason: Option<&str>, has_tool_use_block: bool) -> Value {
    match finish_reason {
        Some("stop") => json!("end_turn"),
        Some("length") => json!("max_tokens"),
        Some("tool_calls") if has_tool_use_block => json!("tool_use"),
        Some("tool_calls") => Value::Null,
        _ => Value::Null,
    }
}

fn stringify_value(value: &Value) -> String {
    serde_json::to_string(value).unwrap_or_else(|_| String::new())
}

fn anthropic_error_response(message: String, error_type: &str) -> Value {
    json!({
        "type": "error",
        "error": {
            "type": error_type,
            "message": message
        }
    })
}

async fn append_log(service: &RequestLogService, entry: RequestLogEntry) {
    let _ = service.append_and_trim(entry, REQUEST_LOG_KEEP).await;
}

fn next_request_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|item| item.as_nanos())
        .unwrap_or(0);
    format!("req_{nanos}")
}
