use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    body::Body,
    extract::{Json, Request, State},
    http::{header, StatusCode},
    response::{IntoResponse, Response},
    routing::post,
    Router,
};
use bytes::Bytes;
use futures_util::{Stream, StreamExt};
use serde_json::{json, Value};
use sqlx::SqlitePool;

use crate::forwarding::executor::{execute_openai_json, execute_openai_stream};
use crate::forwarding::openai_inbound::{
    apply_response, build_observation, effective_model, extract_usage, requested_model,
    stream_requested,
};
use crate::forwarding::types::UsageSnapshot;
use crate::http::passthrough::handle_passthrough_request;
use crate::service::request_log_service::{RequestLogEntry, RequestLogService};
use crate::upstream::openai_client::OpenAiClient;

const REQUEST_LOG_KEEP: i64 = 10_000;

#[derive(Clone)]
pub struct OpenAiRouteState {
    pool: SqlitePool,
    gateway_id: String,
    inbound_protocol: String,
    client: OpenAiClient,
}

impl OpenAiRouteState {
    pub fn new(pool: SqlitePool, gateway_id: impl Into<String>) -> Self {
        Self::new_with_protocol(pool, gateway_id, "openai")
    }

    pub fn new_with_protocol(
        pool: SqlitePool,
        gateway_id: impl Into<String>,
        inbound_protocol: impl Into<String>,
    ) -> Self {
        Self {
            pool,
            gateway_id: gateway_id.into(),
            inbound_protocol: inbound_protocol.into(),
            client: OpenAiClient::new(),
        }
    }
}

pub fn build_openai_router(state: OpenAiRouteState) -> Router {
    Router::new()
        .route("/v1/chat/completions", post(forward_chat_completions))
        .fallback(forward_openai_passthrough)
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
        let mut upstream_payload = payload.clone();
        ensure_openai_stream_include_usage(&mut upstream_payload);

        match execute_openai_stream(
            &state.pool,
            &state.gateway_id,
            &state.client,
            &upstream_payload,
        )
        .await
        {
            Ok((target, status, upstream_response, trace)) => {
                let status_code =
                    StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
                let mut observation =
                    build_observation(&request_id, &state.gateway_id, &target, model.clone(), true);
                observation.apply_route_attempts(
                    trace.provider_id_initial.clone(),
                    trace.route_attempt_count,
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

                    let request_log_service = log_service.clone();
                    let request_log_request_id = request_id.clone();
                    return (
                        status_code,
                        [(header::CONTENT_TYPE, "text/event-stream; charset=utf-8")],
                        Body::from_stream(track_openai_stream_usage(
                            upstream_response.bytes_stream(),
                            request_log_service,
                            request_log_request_id,
                        )),
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
        Ok((target, status, value, trace)) => {
            let status_code =
                StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);
            let latency_ms = started_at.elapsed().as_millis() as i64;
            let mut observation = build_observation(
                &request_id,
                &state.gateway_id,
                &target,
                model.clone(),
                false,
            );
            observation
                .apply_route_attempts(trace.provider_id_initial.clone(), trace.route_attempt_count);
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

async fn forward_openai_passthrough(
    State(state): State<OpenAiRouteState>,
    request: Request,
) -> Response {
    handle_passthrough_request(
        state.pool.clone(),
        &state.gateway_id,
        &state.inbound_protocol,
        reqwest::Client::new(),
        request,
    )
    .await
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

fn track_openai_stream_usage<S, E>(
    upstream: S,
    log_service: RequestLogService,
    request_id: String,
) -> impl Stream<Item = Result<Bytes, anyhow::Error>> + Send + 'static
where
    S: Stream<Item = Result<Bytes, E>> + Send + 'static,
    E: std::error::Error + Send + Sync + 'static,
{
    async_stream::try_stream! {
        let mut tracker = OpenAiStreamUsageTracker::default();
        futures_util::pin_mut!(upstream);

        while let Some(chunk_result) = upstream.next().await {
            let chunk = chunk_result
                .map_err(|err| anyhow::anyhow!("failed to read upstream stream chunk: {err}"))?;
            tracker.push_chunk(chunk.as_ref())?;
            yield chunk;
        }

        if let Some(usage) = tracker.finish()? {
            let _ = log_service.update_usage(&request_id, &usage).await;
        }
    }
}

#[derive(Default)]
struct OpenAiStreamUsageTracker {
    pending: Vec<u8>,
    usage: Option<UsageSnapshot>,
}

impl OpenAiStreamUsageTracker {
    fn push_chunk(&mut self, chunk: &[u8]) -> anyhow::Result<()> {
        self.pending.extend_from_slice(chunk);

        while let Some(line_end) = self.pending.iter().position(|item| *item == b'\n') {
            let mut line = self.pending.drain(..=line_end).collect::<Vec<u8>>();
            trim_sse_line_endings(&mut line);
            self.parse_line(&line)?;
        }

        Ok(())
    }

    fn finish(&mut self) -> anyhow::Result<Option<UsageSnapshot>> {
        if !self.pending.is_empty() {
            let mut line = std::mem::take(&mut self.pending);
            trim_sse_line_endings(&mut line);
            self.parse_line(&line)?;
        }

        Ok(self.usage.clone())
    }

    fn parse_line(&mut self, raw_line: &[u8]) -> anyhow::Result<()> {
        let line = std::str::from_utf8(raw_line)
            .map_err(|err| anyhow::anyhow!("failed to decode openai sse line as utf-8: {err}"))?
            .trim();

        if !line.starts_with("data:") {
            return Ok(());
        }

        let data = line.trim_start_matches("data:").trim();
        if data.is_empty() || data == "[DONE]" {
            return Ok(());
        }

        let event: Value = serde_json::from_str(data)
            .map_err(|err| anyhow::anyhow!("failed to parse openai sse chunk: {err}"))?;

        if let Some(usage) = event.get("usage").and_then(Value::as_object) {
            self.usage = Some(extract_usage(&json!({ "usage": usage })));
        }

        Ok(())
    }
}

fn ensure_openai_stream_include_usage(payload: &mut Value) {
    let Some(object) = payload.as_object_mut() else {
        return;
    };

    let stream_options = object
        .entry("stream_options".to_string())
        .or_insert_with(|| json!({}));

    if let Some(stream_options_object) = stream_options.as_object_mut() {
        stream_options_object.insert("include_usage".to_string(), Value::Bool(true));
    }
}

fn trim_sse_line_endings(line: &mut Vec<u8>) {
    if line.ends_with(b"\n") {
        line.pop();
    }
    if line.ends_with(b"\r") {
        line.pop();
    }
}
