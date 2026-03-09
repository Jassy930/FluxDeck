use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    body::Body,
    extract::{Json, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Router,
};
use serde_json::{json, Value};
use sqlx::SqlitePool;

use crate::forwarding::executor::{execute_openai_json, execute_openai_stream};
use crate::forwarding::openai_inbound::{
    apply_response, build_observation, effective_model, extract_usage, requested_model,
    stream_requested,
};
use crate::service::request_log_service::{RequestLogEntry, RequestLogService};
use crate::upstream::openai_client::OpenAiClient;

const REQUEST_LOG_KEEP: i64 = 10_000;

#[derive(Clone)]
pub struct OpenAiRouteState {
    pool: SqlitePool,
    gateway_id: String,
    client: OpenAiClient,
}

impl OpenAiRouteState {
    pub fn new(pool: SqlitePool, gateway_id: impl Into<String>) -> Self {
        Self {
            pool,
            gateway_id: gateway_id.into(),
            client: OpenAiClient::new(),
        }
    }
}

pub fn build_openai_router(state: OpenAiRouteState) -> Router {
    Router::new()
        .route("/v1/chat/completions", post(forward_chat_completions))
        .with_state(state)
}

async fn forward_chat_completions(
    State(state): State<OpenAiRouteState>,
    Json(payload): Json<Value>,
) -> Response {
    let request_id = next_request_id();
    let model = requested_model(&payload);
    let is_stream = stream_requested(&payload);
    let started_at = Instant::now();
    let log_service = RequestLogService::new(state.pool.clone());

    if is_stream {
        match execute_openai_stream(&state.pool, &state.gateway_id, &state.client, &payload).await {
            Ok((target, status, upstream_response)) => {
                let status_code =
                    StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
                let mut observation = build_observation(
                    &request_id,
                    &state.gateway_id,
                    &target,
                    model.clone(),
                    true,
                );
                let first_byte_ms = started_at.elapsed().as_millis() as i64;

                if status_code.is_success() {
                    let latency_ms = started_at.elapsed().as_millis() as i64;
                    apply_response(
                        &mut observation,
                        i64::from(status_code.as_u16()),
                        latency_ms,
                        first_byte_ms,
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

                let status_value = i64::from(status_code.as_u16());
                let latency_ms = started_at.elapsed().as_millis() as i64;
                let body = upstream_response.text().await.unwrap_or_default();
                observation.status_code = Some(status_value);
                observation.latency_ms = Some(latency_ms);
                observation.first_byte_ms = Some(first_byte_ms);
                observation.error_stage = Some("upstream_response".to_string());
                observation.error_type = Some("upstream_error".to_string());
                append_log(
                    &log_service,
                    RequestLogEntry {
                        request_id: request_id.clone(),
                        gateway_id: state.gateway_id.clone(),
                        provider_id: target.provider_id,
                        model,
                        status_code: status_value,
                        latency_ms,
                        error: Some(body.clone()),
                        observation,
                        usage: Default::default(),
                    },
                )
                .await;

                return (
                    status_code,
                    Json(json!({
                        "error": {
                            "message": if body.is_empty() { "upstream returned an error" } else { &body },
                            "type": "upstream_error",
                            "request_id": request_id
                        }
                    })),
                )
                    .into_response();
            }
            Err(err) => {
                return append_openai_route_error(
                    &log_service,
                    &state.gateway_id,
                    request_id,
                    model,
                    started_at,
                    "unknown".to_string(),
                    StatusCode::BAD_GATEWAY,
                    err.to_string(),
                    "upstream_error",
                )
                .await;
            }
        }
    }

    match execute_openai_json(&state.pool, &state.gateway_id, &state.client, &payload).await {
        Ok((target, status, value)) => {
            let status_code = StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
            let latency_ms = started_at.elapsed().as_millis() as i64;
            let mut observation = build_observation(
                &request_id,
                &state.gateway_id,
                &target,
                model.clone(),
                false,
            );
            apply_response(
                &mut observation,
                i64::from(status_code.as_u16()),
                latency_ms,
                latency_ms,
                effective_model(&value),
            );
            let usage = extract_usage(&value);

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
                    usage,
                },
            )
            .await;

            (status_code, Json(value)).into_response()
        }
        Err(err) => {
            append_openai_route_error(
                &log_service,
                &state.gateway_id,
                request_id,
                model,
                started_at,
                "unknown".to_string(),
                StatusCode::BAD_REQUEST,
                err.to_string(),
                "config_error",
            )
            .await
        }
    }
}

async fn append_log(service: &RequestLogService, entry: RequestLogEntry) {
    let _ = service.append_and_trim(entry, REQUEST_LOG_KEEP).await;
}

async fn append_openai_route_error(
    service: &RequestLogService,
    gateway_id: &str,
    request_id: String,
    model: Option<String>,
    started_at: Instant,
    provider_id: String,
    status_code: StatusCode,
    error: String,
    error_type: &str,
) -> Response {
    append_log(
        service,
        RequestLogEntry {
            request_id: request_id.clone(),
            gateway_id: gateway_id.to_string(),
            provider_id,
            model,
            status_code: i64::from(status_code.as_u16()),
            latency_ms: started_at.elapsed().as_millis() as i64,
            error: Some(error.clone()),
            observation: Default::default(),
            usage: Default::default(),
        },
    )
    .await;

    (
        status_code,
        Json(json!({
            "error": {
                "message": error,
                "type": error_type,
                "request_id": request_id
            }
        })),
    )
        .into_response()
}

fn next_request_id() -> String {
    let nanos = SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|item| item.as_nanos())
        .unwrap_or(0);
    format!("req_{nanos}")
}
