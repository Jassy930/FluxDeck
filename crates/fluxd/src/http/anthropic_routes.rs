use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    body::Body,
    extract::{Json, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Router,
};
use bytes::Bytes;
use futures_util::{Stream, StreamExt};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

use crate::forwarding::anthropic_inbound::{
    apply_response as apply_anthropic_response,
    build_observation as build_anthropic_observation,
    extract_anthropic_usage,
    extract_openai_usage as extract_anthropic_openai_usage,
    usage_from_input_tokens,
};
use crate::protocol::adapters::anthropic::{decode_anthropic_request, AnthropicSseEncoder};
use crate::protocol::adapters::openai::{encode_openai_chat_request, OpenAiSseDecoder};
use crate::protocol::ir::IrRequest;
use crate::protocol::token_count::count_tokens as count_tokens_with_fallback;
use crate::service::request_log_service::{RequestLogEntry, RequestLogService};
use crate::upstream::anthropic_client::AnthropicClient;
use crate::upstream::openai_client::OpenAiClient;

const REQUEST_LOG_KEEP: i64 = 10_000;

#[derive(Clone)]
pub struct AnthropicRouteState {
    pool: SqlitePool,
    gateway_id: String,
    client: OpenAiClient,
    anthropic_client: AnthropicClient,
}

impl AnthropicRouteState {
    pub fn new(pool: SqlitePool, gateway_id: impl Into<String>) -> Self {
        Self {
            pool,
            gateway_id: gateway_id.into(),
            client: OpenAiClient::new(),
            anthropic_client: AnthropicClient::new(),
        }
    }
}

pub fn build_anthropic_router(state: AnthropicRouteState) -> Router {
    Router::new()
        .route("/v1/messages", post(forward_messages))
        .route("/v1/messages/count_tokens", post(count_tokens_handler))
        .with_state(state)
}

async fn forward_messages(
    State(state): State<AnthropicRouteState>,
    Json(payload): Json<Value>,
) -> Response {
    let request_id = next_request_id();
    let mut model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let requested_model = model.clone();
    let stream_requested = payload
        .get("stream")
        .and_then(Value::as_bool)
        .unwrap_or(false);
    let started_at = Instant::now();
    let log_service = RequestLogService::new(state.pool.clone());

    let mut ir = match decode_anthropic_request(&payload) {
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
                    observation: Default::default(),
                    usage: Default::default(),
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
            maybe_log_request_payload(
                "/v1/messages",
                &state.gateway_id,
                &request_id,
                &payload,
                &target.request_debug,
            );

            let strict_unsupported_extensions = strict_unsupported_extension_keys(&ir);
            if target.compatibility_mode == CompatibilityMode::Strict
                && !strict_unsupported_extensions.is_empty()
            {
                let message = format!(
                    "strict compatibility mode does not allow extension fields: {}",
                    strict_unsupported_extensions.join(", ")
                );
                append_log_with_dimensions(
                    &log_service,
                    RequestLogEntry {
                        request_id,
                        gateway_id: state.gateway_id.clone(),
                        provider_id: target.provider_id,
                        model,
                        status_code: i64::from(StatusCode::UNPROCESSABLE_ENTITY.as_u16()),
                        latency_ms: started_at.elapsed().as_millis() as i64,
                        error: Some(message.clone()),
                        observation: Default::default(),
                        usage: Default::default(),
                    },
                    &json!({
                        "compatibility_mode": "strict",
                        "event": "reject_extension_fields",
                        "unsupported_extension_fields": strict_unsupported_extensions
                    }),
                )
                .await;

                return (
                    StatusCode::UNPROCESSABLE_ENTITY,
                    Json(anthropic_error_response(message, "capability_error")),
                )
                    .into_response();
            }

            if let Some(requested_model) = ir.model.as_deref() {
                let resolved_model = target.model_mapping.resolve(requested_model);
                if resolved_model != requested_model {
                    ir.model = Some(resolved_model.clone());
                    model = Some(resolved_model);
                }
            }

            if target.upstream_protocol == "anthropic" {
                let mut native_payload = payload.clone();
                if let Some(effective_model) = model.as_deref() {
                    if requested_model.as_deref() != Some(effective_model) {
                        rewrite_payload_model(&mut native_payload, effective_model);
                    }
                }

                if stream_requested {
                    let response = state
                        .anthropic_client
                        .messages_stream(&target.base_url, &target.api_key, &native_payload)
                        .await;

                    match response {
                        Ok((status, upstream_response)) => {
                            let status_code = StatusCode::from_u16(status.as_u16())
                                .unwrap_or(StatusCode::BAD_GATEWAY);

                            if status_code.is_success() {
                                let latency_ms = started_at.elapsed().as_millis() as i64;
                                let mut observation = build_anthropic_observation(
                                    &request_id,
                                    &state.gateway_id,
                                    &target.provider_id,
                                    &target.upstream_protocol,
                                    requested_model.clone(),
                                    model.clone(),
                                    true,
                                );
                                apply_anthropic_response(
                                    &mut observation,
                                    i64::from(status_code.as_u16()),
                                    latency_ms,
                                    latency_ms,
                                    model.clone(),
                                );
                                append_log(
                                    &log_service,
                                    RequestLogEntry {
                                        request_id: request_id.clone(),
                                        gateway_id: state.gateway_id.clone(),
                                        provider_id: target.provider_id,
                                        model,
                                        status_code: i64::from(status_code.as_u16()),
                                        latency_ms,
                                        error: None,
                                        observation,
                                        usage: Default::default(),
                                    },
                                )
                                .await;

                                return (
                                    status_code,
                                    [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
                                    Body::from_stream(upstream_response.bytes_stream()),
                                )
                                    .into_response();
                            }

                            let message = extract_upstream_error_message_from_text(
                                &upstream_response.text().await.unwrap_or_default(),
                            );
                            return (
                                status_code,
                                Json(anthropic_error_response(message, "api_error")),
                            )
                                .into_response();
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
                                    observation: Default::default(),
                                    usage: Default::default(),
                                },
                            )
                            .await;

                            return (
                                StatusCode::BAD_GATEWAY,
                                Json(anthropic_error_response(
                                    format!("upstream forward failed: {err}"),
                                    "api_error",
                                )),
                            )
                                .into_response();
                        }
                    }
                }

                let response = state
                    .anthropic_client
                    .messages(&target.base_url, &target.api_key, &native_payload)
                    .await;

                match response {
                    Ok((status, value)) => {
                        let status_code = StatusCode::from_u16(status.as_u16())
                            .unwrap_or(StatusCode::BAD_GATEWAY);

                        if status_code.is_success() {
                            let latency_ms = started_at.elapsed().as_millis() as i64;
                            let mut observation = build_anthropic_observation(
                                &request_id,
                                &state.gateway_id,
                                &target.provider_id,
                                &target.upstream_protocol,
                                requested_model.clone(),
                                model.clone(),
                                false,
                            );
                            apply_anthropic_response(
                                &mut observation,
                                i64::from(status_code.as_u16()),
                                latency_ms,
                                latency_ms,
                                value.get("model").and_then(Value::as_str).map(ToOwned::to_owned),
                            );
                            append_log(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id,
                                    model,
                                    status_code: i64::from(status_code.as_u16()),
                                    latency_ms,
                                    error: None,
                                    observation,
                                    usage: extract_anthropic_usage(&value),
                                },
                            )
                            .await;

                            return (status_code, Json(value)).into_response();
                        }

                        let message = value
                            .as_object()
                            .and_then(extract_error_message_from_json_map)
                            .unwrap_or_else(|| summarize_json_for_error(&value));

                        return (
                            status_code,
                            Json(anthropic_error_response(message, "api_error")),
                        )
                            .into_response();
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
                                observation: Default::default(),
                                usage: Default::default(),
                            },
                        )
                        .await;

                        return (
                            StatusCode::BAD_GATEWAY,
                            Json(anthropic_error_response(
                                format!("upstream forward failed: {err}"),
                                "api_error",
                            )),
                        )
                            .into_response();
                    }
                }
            }

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
                            observation: Default::default(),
                            usage: Default::default(),
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

            if target.compatibility_mode == CompatibilityMode::Permissive {
                apply_extension_passthrough(&ir, &mut upstream_payload);
            }

            if stream_requested {
                if let Some(object) = upstream_payload.as_object_mut() {
                    object.insert("stream".to_string(), Value::Bool(true));
                }

                let response = state
                    .client
                    .chat_completions_stream(&target.base_url, &target.api_key, &upstream_payload)
                    .await;

                match response {
                    Ok((status, upstream_response)) => {
                        let status_code = StatusCode::from_u16(status.as_u16())
                            .unwrap_or(StatusCode::BAD_GATEWAY);

                        if status_code.is_success() {
                            let latency_ms = started_at.elapsed().as_millis() as i64;
                            let mut observation = build_anthropic_observation(
                                &request_id,
                                &state.gateway_id,
                                &target.provider_id,
                                &target.upstream_protocol,
                                requested_model.clone(),
                                model.clone(),
                                true,
                            );
                            apply_anthropic_response(
                                &mut observation,
                                i64::from(status_code.as_u16()),
                                latency_ms,
                                latency_ms,
                                model.clone(),
                            );
                            append_log(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id,
                                    model,
                                    status_code: i64::from(status_code.as_u16()),
                                    latency_ms,
                                    error: None,
                                    observation,
                                    usage: Default::default(),
                                },
                            )
                            .await;

                            let anthropic_stream =
                                map_upstream_to_anthropic_stream(upstream_response.bytes_stream());
                            return (
                                status_code,
                                [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
                                Body::from_stream(anthropic_stream),
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
                                observation: Default::default(),
                                usage: Default::default(),
                            },
                        )
                        .await;

                        let raw_sse = upstream_response.text().await.unwrap_or_default();
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
                                observation: Default::default(),
                                usage: Default::default(),
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

                        if status_code.is_success() {
                            let latency_ms = started_at.elapsed().as_millis() as i64;
                            let anthropic_response =
                                crate::forwarding::response_mapping::map_openai_to_anthropic_message(
                                    &value, &ir,
                                );
                            let mut observation = build_anthropic_observation(
                                &request_id,
                                &state.gateway_id,
                                &target.provider_id,
                                &target.upstream_protocol,
                                requested_model.clone(),
                                model.clone(),
                                false,
                            );
                            let effective_model = anthropic_response
                                .get("model")
                                .and_then(Value::as_str)
                                .map(ToOwned::to_owned);
                            apply_anthropic_response(
                                &mut observation,
                                i64::from(status_code.as_u16()),
                                latency_ms,
                                latency_ms,
                                effective_model.clone(),
                            );
                            append_log(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id,
                                    model,
                                    status_code: i64::from(status_code.as_u16()),
                                    latency_ms,
                                    error: None,
                                    observation,
                                    usage: extract_anthropic_openai_usage(&value),
                                },
                            )
                            .await;

                            return (
                                status_code,
                                Json(anthropic_response),
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
                                observation: Default::default(),
                                usage: Default::default(),
                            },
                        )
                        .await;

                        let message = value
                            .as_object()
                            .and_then(extract_error_message_from_json_map)
                            .unwrap_or_else(|| summarize_json_for_error(&value));

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
                                observation: Default::default(),
                                usage: Default::default(),
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
                    observation: Default::default(),
                    usage: Default::default(),
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

async fn count_tokens_handler(
    State(state): State<AnthropicRouteState>,
    Json(mut payload): Json<Value>,
) -> Response {
    let request_id = next_request_id();
    let mut model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let requested_model = model.clone();
    let started_at = Instant::now();
    let log_service = RequestLogService::new(state.pool.clone());

    let mut ir = match decode_anthropic_request(&payload) {
        Ok(ir) => ir,
        Err(err) => {
            append_log(
                &log_service,
                RequestLogEntry {
                    request_id,
                    gateway_id: state.gateway_id.clone(),
                    provider_id: "unknown".to_string(),
                    model: model.clone(),
                    status_code: i64::from(StatusCode::BAD_REQUEST.as_u16()),
                    latency_ms: started_at.elapsed().as_millis() as i64,
                    error: Some(err.to_string()),
                    observation: Default::default(),
                    usage: Default::default(),
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
            maybe_log_request_payload(
                "/v1/messages/count_tokens",
                &state.gateway_id,
                &request_id,
                &payload,
                &target.request_debug,
            );

            if let Some(requested_model) = ir.model.as_deref() {
                let resolved_model = target.model_mapping.resolve(requested_model);
                if resolved_model != requested_model {
                    ir.model = Some(resolved_model.clone());
                    rewrite_payload_model(&mut payload, &resolved_model);
                    model = Some(resolved_model);
                }
            }

            if target.upstream_protocol == "anthropic" {
                let response = state
                    .anthropic_client
                    .messages_count_tokens(&target.base_url, &target.api_key, &payload)
                    .await;

                match response {
                    Ok((status, body)) => {
                        let status_code = StatusCode::from_u16(status.as_u16())
                            .unwrap_or(StatusCode::BAD_GATEWAY);

                        if status_code.is_success() {
                            let Some(upstream_tokens) = extract_upstream_input_tokens(body.as_ref()) else {
                                return (
                                    StatusCode::BAD_GATEWAY,
                                    Json(anthropic_error_response(
                                        "upstream count_tokens response missing `input_tokens`".to_string(),
                                        "api_error",
                                    )),
                                )
                                    .into_response();
                            };

                            let latency_ms = started_at.elapsed().as_millis() as i64;
                            let mut observation = build_anthropic_observation(
                                &request_id,
                                &state.gateway_id,
                                &target.provider_id,
                                &target.upstream_protocol,
                                requested_model.clone(),
                                model.clone(),
                                false,
                            );
                            apply_anthropic_response(
                                &mut observation,
                                i64::from(StatusCode::OK.as_u16()),
                                latency_ms,
                                latency_ms,
                                model.clone(),
                            );
                            append_log(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id,
                                    model: model.clone(),
                                    status_code: i64::from(StatusCode::OK.as_u16()),
                                    latency_ms,
                                    error: None,
                                    observation,
                                    usage: usage_from_input_tokens(upstream_tokens as i64),
                                },
                            )
                            .await;

                            return (
                                StatusCode::OK,
                                Json(json!({
                                    "input_tokens": upstream_tokens,
                                    "estimated": false
                                })),
                            )
                                .into_response();
                        }

                        let message = body
                            .as_ref()
                            .and_then(extract_error_message_from_json)
                            .unwrap_or_else(|| "upstream returned an error".to_string());
                        return (
                            status_code,
                            Json(anthropic_error_response(message, "api_error")),
                        )
                            .into_response();
                    }
                    Err(err) => {
                        return (
                            StatusCode::BAD_GATEWAY,
                            Json(anthropic_error_response(
                                format!("upstream forward failed: {err}"),
                                "api_error",
                            )),
                        )
                            .into_response();
                    }
                }
            }

            let response = state
                .client
                .anthropic_messages_count_tokens(&target.base_url, &target.api_key, &payload)
                .await;

            match response {
                Ok((status, body)) => {
                    let status_code =
                        StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);

                    if status_code.is_success() {
                        let Some(upstream_tokens) = extract_upstream_input_tokens(body.as_ref())
                        else {
                            append_log(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id.clone(),
                                    model: model.clone(),
                                    status_code: i64::from(StatusCode::BAD_GATEWAY.as_u16()),
                                    latency_ms: started_at.elapsed().as_millis() as i64,
                                    error: Some(
                                        "upstream count_tokens response missing input_tokens"
                                            .to_string(),
                                    ),
                                    observation: Default::default(),
                                    usage: Default::default(),
                                },
                            )
                            .await;

                            return (
                                StatusCode::BAD_GATEWAY,
                                Json(anthropic_error_response(
                                    "upstream count_tokens response missing `input_tokens`"
                                        .to_string(),
                                    "api_error",
                                )),
                            )
                                .into_response();
                        };

                        let counted = count_tokens_with_fallback(&ir, Some(upstream_tokens));
                        append_log(
                            &log_service,
                            RequestLogEntry {
                                request_id: request_id.clone(),
                                gateway_id: state.gateway_id.clone(),
                                provider_id: target.provider_id.clone(),
                                model: model.clone(),
                                status_code: i64::from(StatusCode::OK.as_u16()),
                                latency_ms: started_at.elapsed().as_millis() as i64,
                                error: None,
                                observation: Default::default(),
                                usage: Default::default(),
                            },
                        )
                        .await;

                        return (
                            StatusCode::OK,
                            Json(json!({
                                "input_tokens": counted.input_tokens,
                                "estimated": counted.estimated
                            })),
                        )
                            .into_response();
                    }

                    if is_count_tokens_unsupported(status_code) {
                        if target.compatibility_mode == CompatibilityMode::Strict {
                            let message =
                                "upstream does not support count_tokens in strict mode".to_string();
                            append_log_with_dimensions(
                                &log_service,
                                RequestLogEntry {
                                    request_id: request_id.clone(),
                                    gateway_id: state.gateway_id.clone(),
                                    provider_id: target.provider_id.clone(),
                                    model: model.clone(),
                                    status_code: i64::from(
                                        StatusCode::UNPROCESSABLE_ENTITY.as_u16(),
                                    ),
                                    latency_ms: started_at.elapsed().as_millis() as i64,
                                    error: Some(message.clone()),
                                    observation: Default::default(),
                                    usage: Default::default(),
                                },
                                &json!({
                                    "compatibility_mode": "strict",
                                    "event": "count_tokens_unsupported"
                                }),
                            )
                            .await;

                            return (
                                StatusCode::UNPROCESSABLE_ENTITY,
                                Json(anthropic_error_response(message, "capability_error")),
                            )
                                .into_response();
                        }

                        let counted = count_tokens_with_fallback(&ir, None);
                        append_log_with_dimensions(
                            &log_service,
                            RequestLogEntry {
                                request_id: request_id.clone(),
                                gateway_id: state.gateway_id.clone(),
                                provider_id: target.provider_id.clone(),
                                model: model.clone(),
                                status_code: i64::from(StatusCode::OK.as_u16()),
                                latency_ms: started_at.elapsed().as_millis() as i64,
                                error: None,
                                observation: Default::default(),
                                usage: Default::default(),
                            },
                            &json!({
                                "compatibility_mode": match target.compatibility_mode {
                                    CompatibilityMode::Permissive => "permissive",
                                    _ => "compatible"
                                },
                                "event": "degraded_to_estimate"
                            }),
                        )
                        .await;

                        return (
                            StatusCode::OK,
                            Json(json!({
                                "input_tokens": counted.input_tokens,
                                "estimated": counted.estimated,
                                "notice": "degraded_to_estimate"
                            })),
                        )
                            .into_response();
                    }

                    let message = body
                        .as_ref()
                        .and_then(extract_error_message_from_json)
                        .unwrap_or_else(|| "upstream returned an error".to_string());

                    append_log(
                        &log_service,
                        RequestLogEntry {
                            request_id: request_id.clone(),
                            gateway_id: state.gateway_id.clone(),
                            provider_id: target.provider_id,
                            model: model.clone(),
                            status_code: i64::from(status_code.as_u16()),
                            latency_ms: started_at.elapsed().as_millis() as i64,
                            error: None,
                            observation: Default::default(),
                            usage: Default::default(),
                        },
                    )
                    .await;

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
                            model: model.clone(),
                            status_code: i64::from(StatusCode::BAD_GATEWAY.as_u16()),
                            latency_ms: started_at.elapsed().as_millis() as i64,
                            error: Some(err.to_string()),
                            observation: Default::default(),
                            usage: Default::default(),
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
        Err(err) => {
            append_log(
                &log_service,
                RequestLogEntry {
                    request_id,
                    gateway_id: state.gateway_id.clone(),
                    provider_id: "unknown".to_string(),
                    model: model.clone(),
                    status_code: i64::from(StatusCode::BAD_REQUEST.as_u16()),
                    latency_ms: started_at.elapsed().as_millis() as i64,
                    error: Some(err.to_string()),
                    observation: Default::default(),
                    usage: Default::default(),
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

fn map_upstream_to_anthropic_stream<S, E>(
    upstream: S,
) -> impl Stream<Item = Result<Bytes, anyhow::Error>> + Send + 'static
where
    S: Stream<Item = Result<Bytes, E>> + Send + 'static,
    E: std::error::Error + Send + Sync + 'static,
{
    async_stream::try_stream! {
        let mut decoder = OpenAiSseDecoder::new();
        let mut encoder = AnthropicSseEncoder::new();
        futures_util::pin_mut!(upstream);

        while let Some(chunk_result) = upstream.next().await {
            let chunk = chunk_result
                .map_err(|err| anyhow::anyhow!("failed to read upstream stream chunk: {err}"))?;
            let events = decoder.push_chunk(chunk.as_ref())?;
            for event in events {
                let encoded = encoder.encode_event(&event);
                if !encoded.is_empty() {
                    yield Bytes::from(encoded);
                }
            }
        }

        let tail_events = decoder.finish()?;
        for event in tail_events {
            let encoded = encoder.encode_event(&event);
            if !encoded.is_empty() {
                yield Bytes::from(encoded);
            }
        }
    }
}

fn extract_upstream_error_message_from_text(body: &str) -> String {
    if let Some(message) = extract_json_error_message_from_text(body) {
        return message;
    }

    for raw_line in body.lines() {
        let line = raw_line.trim();
        if !line.starts_with("data:") {
            continue;
        }

        let data = line.trim_start_matches("data:").trim();
        if data.is_empty() || data == "[DONE]" {
            continue;
        }

        if let Some(message) = extract_json_error_message_from_text(data) {
            return message;
        }
    }

    let trimmed = body.trim();
    if trimmed.is_empty() {
        "upstream returned an error".to_string()
    } else {
        trimmed.to_string()
    }
}

fn extract_json_error_message_from_text(body: &str) -> Option<String> {
    let value = serde_json::from_str::<Value>(body).ok()?;
    value
        .as_object()
        .and_then(extract_error_message_from_json_map)
}

fn extract_upstream_input_tokens(body: Option<&Value>) -> Option<u64> {
    body.and_then(|item| item.get("input_tokens"))
        .and_then(Value::as_u64)
}

fn extract_error_message_from_json(body: &Value) -> Option<String> {
    body.as_object()
        .and_then(extract_error_message_from_json_map)
}

fn extract_error_message_from_json_map(body: &serde_json::Map<String, Value>) -> Option<String> {
    body.get("error")
        .and_then(|item| item.get("message"))
        .and_then(Value::as_str)
        .map(ToOwned::to_owned)
        .or_else(|| {
            body.get("message")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .or_else(|| {
            body.get("msg")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .or_else(|| {
            body.get("detail")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .or_else(|| {
            body.get("error_description")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
        .or_else(|| {
            body.get("error")
                .and_then(Value::as_str)
                .map(ToOwned::to_owned)
        })
}

fn summarize_json_for_error(value: &Value) -> String {
    let raw = serde_json::to_string(value).unwrap_or_else(|_| String::new());
    if raw.is_empty() {
        return "upstream returned an error".to_string();
    }

    const LIMIT: usize = 240;
    if raw.len() <= LIMIT {
        return raw;
    }
    format!("{}...", &raw[..LIMIT])
}

fn is_count_tokens_unsupported(status: StatusCode) -> bool {
    matches!(
        status,
        StatusCode::NOT_FOUND | StatusCode::METHOD_NOT_ALLOWED | StatusCode::NOT_IMPLEMENTED
    )
}

#[derive(Debug)]
struct ProviderRoutingTarget {
    provider_id: String,
    base_url: String,
    api_key: String,
    upstream_protocol: String,
    compatibility_mode: CompatibilityMode,
    model_mapping: ModelMappingConfig,
    request_debug: RequestDebugConfig,
}

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
enum CompatibilityMode {
    Strict,
    Compatible,
    Permissive,
}

impl CompatibilityMode {
    fn from_protocol_config(config: &Value) -> Self {
        let mode = config
            .get("compatibility_mode")
            .and_then(Value::as_str)
            .unwrap_or("compatible");
        match mode {
            "strict" => CompatibilityMode::Strict,
            "permissive" => CompatibilityMode::Permissive,
            _ => CompatibilityMode::Compatible,
        }
    }
}

#[derive(Debug, Clone, Default)]
struct ModelMappingConfig {
    fallback_model: Option<String>,
    rules: Vec<ModelMappingRule>,
}

#[derive(Debug, Clone)]
struct ModelMappingRule {
    from: String,
    to: String,
}

impl ModelMappingConfig {
    fn from_protocol_config(config: &Value) -> Self {
        let Some(mapping) = config.get("model_mapping").and_then(Value::as_object) else {
            return Self::default();
        };

        if matches!(mapping.get("enabled").and_then(Value::as_bool), Some(false)) {
            return Self::default();
        }

        let fallback_model = mapping
            .get("fallback_model")
            .and_then(Value::as_str)
            .map(str::trim)
            .filter(|item| !item.is_empty())
            .map(ToOwned::to_owned);

        let rules = mapping
            .get("rules")
            .and_then(Value::as_array)
            .map(|items| {
                items
                    .iter()
                    .filter_map(|item| {
                        let object = item.as_object()?;
                        let from = object.get("from")?.as_str()?.trim();
                        let to = object.get("to")?.as_str()?.trim();
                        if from.is_empty() || to.is_empty() {
                            return None;
                        }
                        Some(ModelMappingRule {
                            from: from.to_string(),
                            to: to.to_string(),
                        })
                    })
                    .collect::<Vec<_>>()
            })
            .unwrap_or_default();

        Self {
            fallback_model,
            rules,
        }
    }

    fn resolve(&self, requested_model: &str) -> String {
        for rule in &self.rules {
            if model_pattern_matches(&rule.from, requested_model) {
                return rule.to.clone();
            }
        }

        if let Some(fallback) = &self.fallback_model {
            return fallback.clone();
        }

        requested_model.to_string()
    }
}

#[derive(Debug, Clone)]
struct RequestDebugConfig {
    log_request_payload: bool,
    max_payload_chars: usize,
}

impl Default for RequestDebugConfig {
    fn default() -> Self {
        Self {
            log_request_payload: false,
            max_payload_chars: 4_000,
        }
    }
}

impl RequestDebugConfig {
    fn from_protocol_config(config: &Value) -> Self {
        let mut parsed = Self::default();
        let Some(debug) = config.get("debug").and_then(Value::as_object) else {
            return parsed;
        };

        if let Some(enabled) = debug.get("log_request_payload").and_then(Value::as_bool) {
            parsed.log_request_payload = enabled;
        }
        if let Some(max_chars) = debug.get("max_payload_chars").and_then(Value::as_u64) {
            // Clamp range to avoid huge line output or accidentally empty logs.
            parsed.max_payload_chars = max_chars.clamp(64, 200_000) as usize;
        }

        parsed
    }

    fn enabled(&self) -> bool {
        self.log_request_payload || env_debug_logging_enabled()
    }
}

fn strict_unsupported_extension_keys(ir: &IrRequest) -> Vec<String> {
    ir.extensions
        .keys()
        .filter(|key| !is_strict_known_extension_field(key))
        .cloned()
        .collect()
}

fn is_strict_known_extension_field(key: &str) -> bool {
    matches!(
        key,
        "max_tokens"
            | "max_output_tokens"
            | "temperature"
            | "top_p"
            | "top_k"
            | "metadata"
            | "stream"
            | "stop_sequences"
            | "tool_choice"
            | "thinking"
            | "service_tier"
            | "betas"
    )
}

async fn fetch_provider_target(
    state: &AnthropicRouteState,
) -> anyhow::Result<ProviderRoutingTarget> {
    let row = sqlx::query(
        r#"
        SELECT p.id AS provider_id, p.kind AS provider_kind, p.base_url, p.api_key, g.protocol_config_json, g.upstream_protocol
        FROM gateways g
        JOIN providers p ON p.id = g.default_provider_id
        WHERE g.id = ?1
        "#,
    )
    .bind(&state.gateway_id)
    .fetch_optional(&state.pool)
    .await?;

    let row = row.ok_or_else(|| anyhow::anyhow!("gateway not found: {}", state.gateway_id))?;
    let protocol_config_json: Value =
        serde_json::from_str(&row.get::<String, _>("protocol_config_json"))
            .unwrap_or_else(|_| json!({}));
    let configured_protocol = row.get::<String, _>("upstream_protocol");
    let provider_kind = row.get::<String, _>("provider_kind");
    let upstream_protocol = if configured_protocol == "provider_default" {
        provider_kind
    } else {
        configured_protocol
    };

    Ok(ProviderRoutingTarget {
        provider_id: row.get("provider_id"),
        base_url: row.get("base_url"),
        api_key: row.get("api_key"),
        upstream_protocol,
        compatibility_mode: CompatibilityMode::from_protocol_config(&protocol_config_json),
        model_mapping: ModelMappingConfig::from_protocol_config(&protocol_config_json),
        request_debug: RequestDebugConfig::from_protocol_config(&protocol_config_json),
    })
}

fn apply_extension_passthrough(ir: &IrRequest, upstream_payload: &mut Value) {
    let Some(payload) = upstream_payload.as_object_mut() else {
        return;
    };

    for (key, value) in &ir.extensions {
        if payload.contains_key(key) {
            continue;
        }
        payload.insert(key.clone(), value.clone());
    }
}

fn rewrite_payload_model(payload: &mut Value, model: &str) {
    let Some(object) = payload.as_object_mut() else {
        return;
    };
    object.insert("model".to_string(), Value::String(model.to_string()));
}

fn env_debug_logging_enabled() -> bool {
    match std::env::var("FLUXDECK_DEBUG_ANTHROPIC_REQUEST_PAYLOAD") {
        Ok(raw) => matches!(
            raw.to_ascii_lowercase().as_str(),
            "1" | "true" | "yes" | "on"
        ),
        Err(_) => false,
    }
}

fn maybe_log_request_payload(
    route: &str,
    gateway_id: &str,
    request_id: &str,
    payload: &Value,
    debug: &RequestDebugConfig,
) {
    if !debug.enabled() {
        return;
    }

    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .unwrap_or("unknown");
    let stream = payload
        .get("stream")
        .and_then(Value::as_bool)
        .map(|item| item.to_string())
        .unwrap_or_else(|| "false".to_string());
    let max_tokens = payload
        .get("max_tokens")
        .or_else(|| payload.get("max_output_tokens"))
        .map(stringify_value)
        .unwrap_or_else(|| "null".to_string());
    let messages_len = payload
        .get("messages")
        .and_then(Value::as_array)
        .map(|items| items.len())
        .unwrap_or(0);

    let serialized = serde_json::to_string(payload).unwrap_or_else(|_| "{}".to_string());
    let payload_preview = truncate_chars(&serialized, debug.max_payload_chars);

    println!(
        "[fluxd][anthropic-debug] gateway_id={gateway_id} request_id={request_id} route={route} model={model} stream={stream} max_tokens={max_tokens} messages={messages_len} payload={payload_preview}"
    );
}

fn truncate_chars(raw: &str, max_chars: usize) -> String {
    if raw.chars().count() <= max_chars {
        return raw.to_string();
    }
    let mut truncated = raw.chars().take(max_chars).collect::<String>();
    truncated.push_str("...");
    truncated
}

fn model_pattern_matches(pattern: &str, model: &str) -> bool {
    if pattern == "*" {
        return true;
    }
    if !pattern.contains('*') {
        return pattern == model;
    }

    let starts_with_wildcard = pattern.starts_with('*');
    let ends_with_wildcard = pattern.ends_with('*');
    let segments: Vec<&str> = pattern.split('*').filter(|item| !item.is_empty()).collect();
    if segments.is_empty() {
        return true;
    }

    let mut remainder = model;
    let mut start_index = 0;

    if !starts_with_wildcard {
        let first = segments[0];
        if !remainder.starts_with(first) {
            return false;
        }
        remainder = &remainder[first.len()..];
        start_index = 1;
    }

    let end_index = if ends_with_wildcard {
        segments.len()
    } else {
        segments.len().saturating_sub(1)
    };

    for segment in &segments[start_index..end_index] {
        let Some(position) = remainder.find(segment) else {
            return false;
        };
        remainder = &remainder[position + segment.len()..];
    }

    if !ends_with_wildcard {
        if let Some(last) = segments.last() {
            return remainder.ends_with(last);
        }
    }

    true
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

async fn append_log_with_dimensions(
    service: &RequestLogService,
    entry: RequestLogEntry,
    dimensions: &Value,
) {
    let _ = service
        .append_and_trim_with_dimensions(entry, REQUEST_LOG_KEEP, dimensions)
        .await;
}

fn next_request_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|item| item.as_nanos())
        .unwrap_or(0);
    format!("req_{nanos}")
}

#[cfg(test)]
mod tests {
    use super::{truncate_chars, RequestDebugConfig};
    use serde_json::json;

    #[test]
    fn request_debug_config_defaults_to_disabled() {
        let config = RequestDebugConfig::from_protocol_config(&json!({}));
        assert!(!config.log_request_payload);
        assert_eq!(config.max_payload_chars, 4_000);
    }

    #[test]
    fn request_debug_config_reads_protocol_config() {
        let config = RequestDebugConfig::from_protocol_config(&json!({
            "debug": {
                "log_request_payload": true,
                "max_payload_chars": 120
            }
        }));
        assert!(config.log_request_payload);
        assert_eq!(config.max_payload_chars, 120);
    }

    #[test]
    fn truncate_chars_preserves_utf8() {
        let input = "你好，世界";
        assert_eq!(truncate_chars(input, 2), "你好...");
        assert_eq!(truncate_chars(input, 16), input);
    }
}
