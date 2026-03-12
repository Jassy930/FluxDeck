use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    body::{to_bytes, Body},
    extract::{Request, State},
    http::{header, HeaderName, StatusCode},
    response::{IntoResponse, Response},
    Json, Router,
};
use bytes::Bytes;
use futures_util::{Stream, StreamExt};
use serde_json::json;
use sqlx::SqlitePool;

use crate::forwarding::anthropic_inbound::extract_anthropic_usage;
use crate::forwarding::openai_inbound::extract_usage as extract_openai_usage;
use crate::forwarding::target_resolver::TargetResolver;
use crate::forwarding::types::ForwardObservation;
use crate::service::request_log_service::{RequestLogEntry, RequestLogService};

const REQUEST_LOG_KEEP: i64 = 10_000;

#[derive(Clone)]
pub struct PassthroughRouteState {
    pool: SqlitePool,
    gateway_id: String,
    inbound_protocol: String,
    client: reqwest::Client,
}

impl PassthroughRouteState {
    pub fn new(
        pool: SqlitePool,
        gateway_id: impl Into<String>,
        inbound_protocol: impl Into<String>,
    ) -> Self {
        Self {
            pool,
            gateway_id: gateway_id.into(),
            inbound_protocol: inbound_protocol.into(),
            client: reqwest::Client::new(),
        }
    }
}

pub fn build_passthrough_router(state: PassthroughRouteState) -> Router {
    Router::new()
        .fallback(forward_passthrough)
        .with_state(state)
}

pub async fn handle_passthrough_request(
    pool: SqlitePool,
    gateway_id: &str,
    inbound_protocol: &str,
    client: reqwest::Client,
    request: Request,
) -> Response {
    let request_id = next_request_id();
    let started_at = Instant::now();
    let log_service = RequestLogService::new(pool.clone());
    let resolver = TargetResolver::new(pool);
    let target = match resolver.resolve(gateway_id).await {
        Ok(target) => target,
        Err(err) => {
            append_passthrough_log(
                &log_service,
                request_id,
                gateway_id,
                "unknown",
                inbound_protocol,
                "unknown",
                StatusCode::BAD_GATEWAY,
                started_at,
                Some(format!("resolve gateway target failed: {err}")),
                Some(("resolve_target", "config_error")),
                Default::default(),
                false,
            )
            .await;
            return (
                StatusCode::BAD_GATEWAY,
                Json(json!({
                    "error": {
                        "message": format!("resolve gateway target failed: {err}"),
                        "type": "config_error"
                    }
                })),
            )
                .into_response();
        }
    };

    if target.upstream_protocol != inbound_protocol {
        append_passthrough_log(
            &log_service,
            request_id,
            gateway_id,
            &target.provider_id,
            inbound_protocol,
            &target.upstream_protocol,
            StatusCode::NOT_IMPLEMENTED,
            started_at,
            Some(format!(
                "passthrough fallback only supports same-protocol forwarding, got inbound `{inbound_protocol}` and upstream `{}`",
                target.upstream_protocol
            )),
            Some(("protocol_match", "unsupported_protocol_bridge")),
            Default::default(),
            false,
        )
        .await;
        return (
            StatusCode::NOT_IMPLEMENTED,
            Json(json!({
                "error": {
                    "message": format!(
                        "passthrough fallback only supports same-protocol forwarding, got inbound `{inbound_protocol}` and upstream `{}`",
                        target.upstream_protocol
                    ),
                    "type": "unsupported_protocol_bridge"
                }
            })),
        )
            .into_response();
    }

    let (parts, body) = request.into_parts();
    let path = parts.uri.path().to_string();
    let query = parts.uri.query().map(ToOwned::to_owned);
    let url = build_upstream_url(&target.base_url, &path, query.as_deref());
    let body = match to_bytes(body, usize::MAX).await {
        Ok(body) => body,
        Err(err) => {
            append_passthrough_log(
                &log_service,
                request_id,
                gateway_id,
                &target.provider_id,
                inbound_protocol,
                &target.upstream_protocol,
                StatusCode::BAD_REQUEST,
                started_at,
                Some(format!("read request body failed: {err}")),
                Some(("read_body", "invalid_request_body")),
                Default::default(),
                false,
            )
            .await;
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": {
                        "message": format!("read request body failed: {err}"),
                        "type": "invalid_request_body"
                    }
                })),
            )
                .into_response();
        }
    };

    let mut upstream = client.request(parts.method, url);

    for (name, value) in &parts.headers {
        if should_forward_request_header(name) {
            upstream = upstream.header(name, value);
        }
    }

    upstream = apply_protocol_auth(
        upstream,
        &target.upstream_protocol,
        &target.api_key,
        &parts.headers,
    );

    if !body.is_empty() {
        upstream = upstream.body(body);
    }

    let response = match upstream.send().await {
        Ok(response) => response,
        Err(err) => {
            append_passthrough_log(
                &log_service,
                request_id,
                gateway_id,
                &target.provider_id,
                inbound_protocol,
                &target.upstream_protocol,
                StatusCode::BAD_GATEWAY,
                started_at,
                Some(format!("passthrough upstream request failed: {err}")),
                Some(("upstream_request", "upstream_error")),
                Default::default(),
                false,
            )
            .await;
            return (
                StatusCode::BAD_GATEWAY,
                Json(json!({
                    "error": {
                        "message": format!("passthrough upstream request failed: {err}"),
                        "type": "upstream_error"
                    }
                })),
            )
                .into_response();
        }
    };

    let status = response.status();
    let headers = response.headers().clone();
    let is_stream = headers
        .get(header::CONTENT_TYPE)
        .and_then(|value| value.to_str().ok())
        .is_some_and(|value| value.starts_with("text/event-stream"));

    if is_stream {
        append_passthrough_log(
            &log_service,
            request_id.clone(),
            gateway_id,
            &target.provider_id,
            inbound_protocol,
            &target.upstream_protocol,
            status,
            started_at,
            None,
            None,
            Default::default(),
            true,
        )
        .await;

        let tracked_stream = track_passthrough_stream_usage(
            response.bytes_stream(),
            log_service.clone(),
            request_id,
            target.upstream_protocol.clone(),
        );

        let mut builder = Response::builder().status(status);
        for (name, value) in &headers {
            if should_forward_response_header(name) {
                builder = builder.header(name, value);
            }
        }

        return builder
            .body(Body::from_stream(tracked_stream))
            .unwrap_or_else(|err| {
                (
                    StatusCode::BAD_GATEWAY,
                    Json(json!({
                        "error": {
                            "message": format!("build passthrough response failed: {err}"),
                            "type": "gateway_response_error"
                        }
                    })),
                )
                    .into_response()
            });
    }

    let response_body = match response.bytes().await {
        Ok(body) => body,
        Err(err) => {
            append_passthrough_log(
                &log_service,
                request_id,
                gateway_id,
                &target.provider_id,
                inbound_protocol,
                &target.upstream_protocol,
                StatusCode::BAD_GATEWAY,
                started_at,
                Some(format!("read passthrough upstream response failed: {err}")),
                Some(("read_upstream_response", "upstream_response_error")),
                Default::default(),
                false,
            )
            .await;
            return (
                StatusCode::BAD_GATEWAY,
                Json(json!({
                    "error": {
                        "message": format!("read passthrough upstream response failed: {err}"),
                        "type": "upstream_response_error"
                    }
                })),
            )
                .into_response();
        }
    };

    let usage = if status.is_success() {
        extract_passthrough_usage(&target.upstream_protocol, &response_body)
    } else {
        Default::default()
    };
    append_passthrough_log(
        &log_service,
        request_id,
        gateway_id,
        &target.provider_id,
        inbound_protocol,
        &target.upstream_protocol,
        status,
        started_at,
        None,
        None,
        usage,
        false,
    )
    .await;

    let mut builder = Response::builder().status(status);
    for (name, value) in &headers {
        if should_forward_response_header(name) {
            builder = builder.header(name, value);
        }
    }

    builder
        .body(Body::from(response_body))
        .unwrap_or_else(|err| {
            (
                StatusCode::BAD_GATEWAY,
                Json(json!({
                    "error": {
                        "message": format!("build passthrough response failed: {err}"),
                        "type": "gateway_response_error"
                    }
                })),
            )
                .into_response()
        })
}

async fn forward_passthrough(
    State(state): State<PassthroughRouteState>,
    request: Request,
) -> Response {
    handle_passthrough_request(
        state.pool.clone(),
        &state.gateway_id,
        &state.inbound_protocol,
        state.client.clone(),
        request,
    )
    .await
}

async fn append_passthrough_log(
    service: &RequestLogService,
    request_id: String,
    gateway_id: &str,
    provider_id: &str,
    inbound_protocol: &str,
    upstream_protocol: &str,
    status_code: StatusCode,
    started_at: Instant,
    error: Option<String>,
    error_details: Option<(&str, &str)>,
    usage: crate::forwarding::types::UsageSnapshot,
    is_stream: bool,
) {
    let latency_ms = started_at.elapsed().as_millis() as i64;
    let mut observation = ForwardObservation::new(request_id.clone(), gateway_id.to_string());
    observation.provider_id = Some(provider_id.to_string());
    observation.inbound_protocol = Some(inbound_protocol.to_string());
    observation.upstream_protocol = Some(upstream_protocol.to_string());
    observation.is_stream = is_stream;
    observation.status_code = Some(i64::from(status_code.as_u16()));
    observation.latency_ms = Some(latency_ms);
    if let Some((stage, error_type)) = error_details {
        observation.error_stage = Some(stage.to_string());
        observation.error_type = Some(error_type.to_string());
    }

    let _ = service
        .append_and_trim(
            RequestLogEntry {
                request_id,
                gateway_id: gateway_id.to_string(),
                provider_id: provider_id.to_string(),
                model: None,
                status_code: i64::from(status_code.as_u16()),
                latency_ms,
                error,
                observation,
                usage,
            },
            REQUEST_LOG_KEEP,
        )
        .await;
}

fn extract_passthrough_usage(
    upstream_protocol: &str,
    response_body: &[u8],
) -> crate::forwarding::types::UsageSnapshot {
    let Ok(response) = serde_json::from_slice::<serde_json::Value>(response_body) else {
        return Default::default();
    };

    match upstream_protocol {
        "openai" | "openai-response" => extract_openai_usage(&response),
        "anthropic" => extract_anthropic_usage(&response),
        _ => Default::default(),
    }
}

fn track_passthrough_stream_usage<S, E>(
    upstream: S,
    log_service: RequestLogService,
    request_id: String,
    upstream_protocol: String,
) -> impl Stream<Item = Result<Bytes, anyhow::Error>> + Send + 'static
where
    S: Stream<Item = Result<Bytes, E>> + Send + 'static,
    E: std::error::Error + Send + Sync + 'static,
{
    async_stream::try_stream! {
        let mut tracker = PassthroughStreamUsageTracker::new(upstream_protocol);
        futures_util::pin_mut!(upstream);

        while let Some(chunk_result) = upstream.next().await {
            let chunk = chunk_result
                .map_err(|err| anyhow::anyhow!("failed to read passthrough stream chunk: {err}"))?;
            tracker.push_chunk(chunk.as_ref())?;
            yield chunk;
        }

        if let Some(usage) = tracker.finish()? {
            let _ = log_service.update_usage(&request_id, &usage).await;
        }
    }
}

struct PassthroughStreamUsageTracker {
    upstream_protocol: String,
    pending: Vec<u8>,
    usage: Option<crate::forwarding::types::UsageSnapshot>,
}

impl PassthroughStreamUsageTracker {
    fn new(upstream_protocol: String) -> Self {
        Self {
            upstream_protocol,
            pending: Vec::new(),
            usage: None,
        }
    }

    fn push_chunk(&mut self, chunk: &[u8]) -> anyhow::Result<()> {
        self.pending.extend_from_slice(chunk);

        while let Some(line_end) = self.pending.iter().position(|item| *item == b'\n') {
            let mut line = self.pending.drain(..=line_end).collect::<Vec<u8>>();
            trim_sse_line_endings(&mut line);
            self.parse_line(&line)?;
        }

        Ok(())
    }

    fn finish(&mut self) -> anyhow::Result<Option<crate::forwarding::types::UsageSnapshot>> {
        if !self.pending.is_empty() {
            let mut line = std::mem::take(&mut self.pending);
            trim_sse_line_endings(&mut line);
            self.parse_line(&line)?;
        }

        Ok(self.usage.clone())
    }

    fn parse_line(&mut self, raw_line: &[u8]) -> anyhow::Result<()> {
        let line = std::str::from_utf8(raw_line)
            .map_err(|err| {
                anyhow::anyhow!("failed to decode passthrough sse line as utf-8: {err}")
            })?
            .trim();

        if !line.starts_with("data:") {
            return Ok(());
        }

        let data = line.trim_start_matches("data:").trim();
        if data.is_empty() || data == "[DONE]" {
            return Ok(());
        }

        let event: serde_json::Value = serde_json::from_str(data)
            .map_err(|err| anyhow::anyhow!("failed to parse passthrough sse chunk: {err}"))?;

        self.usage = extract_passthrough_stream_usage(&self.upstream_protocol, &event)
            .or(self.usage.clone());
        Ok(())
    }
}

fn extract_passthrough_stream_usage(
    upstream_protocol: &str,
    event: &serde_json::Value,
) -> Option<crate::forwarding::types::UsageSnapshot> {
    match upstream_protocol {
        "openai" | "openai-response" => {
            if let Some(usage) = event
                .get("response")
                .and_then(|response| response.get("usage"))
            {
                let snapshot = extract_openai_usage(&json!({ "usage": usage }));
                if snapshot.total_tokens.is_some() {
                    return Some(snapshot);
                }
            }

            let snapshot = extract_openai_usage(event);
            snapshot.total_tokens.map(|_| snapshot)
        }
        "anthropic" => {
            let snapshot = extract_anthropic_usage(event);
            snapshot.total_tokens.map(|_| snapshot)
        }
        _ => None,
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

fn build_upstream_url(base_url: &str, path: &str, query: Option<&str>) -> String {
    let normalized_base = base_url.trim_end_matches('/');
    let normalized_path = if normalized_base.ends_with("/v1") && path.starts_with("/v1/") {
        path.trim_start_matches("/v1/")
    } else {
        path.trim_start_matches('/')
    };

    let mut url = if normalized_path.is_empty() {
        normalized_base.to_string()
    } else {
        format!("{normalized_base}/{normalized_path}")
    };

    if let Some(query) = query {
        url.push('?');
        url.push_str(query);
    }

    url
}

fn apply_protocol_auth(
    builder: reqwest::RequestBuilder,
    upstream_protocol: &str,
    api_key: &str,
    original_headers: &axum::http::HeaderMap,
) -> reqwest::RequestBuilder {
    match upstream_protocol {
        "anthropic" => {
            let builder = if api_key.is_empty() {
                builder
            } else {
                builder.header("x-api-key", api_key)
            };
            if original_headers.contains_key("anthropic-version") {
                builder
            } else {
                builder.header("anthropic-version", "2023-06-01")
            }
        }
        _ => {
            if api_key.is_empty() {
                builder
            } else {
                builder.bearer_auth(api_key)
            }
        }
    }
}

fn should_forward_request_header(name: &HeaderName) -> bool {
    !matches!(
        name.as_str(),
        "authorization"
            | "x-api-key"
            | "host"
            | "content-length"
            | "connection"
            | "keep-alive"
            | "proxy-authenticate"
            | "proxy-authorization"
            | "te"
            | "trailer"
            | "transfer-encoding"
            | "upgrade"
    )
}

fn should_forward_response_header(name: &HeaderName) -> bool {
    !matches!(
        name.as_str(),
        "connection"
            | "keep-alive"
            | "proxy-authenticate"
            | "proxy-authorization"
            | "te"
            | "trailer"
            | "transfer-encoding"
            | "upgrade"
    ) && *name != header::CONTENT_LENGTH
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
    use super::build_upstream_url;

    #[test]
    fn preserves_single_v1_prefix_for_versioned_base_url() {
        assert_eq!(
            build_upstream_url("https://api.openai.com/v1", "/v1/responses", None),
            "https://api.openai.com/v1/responses"
        );
    }

    #[test]
    fn appends_unversioned_path_to_versioned_base_url() {
        assert_eq!(
            build_upstream_url(
                "https://api.openai.com/v1",
                "/responses",
                Some("stream=true")
            ),
            "https://api.openai.com/v1/responses?stream=true"
        );
    }
}
