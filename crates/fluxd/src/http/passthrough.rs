use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    body::{to_bytes, Body},
    extract::{Request, State},
    http::{header, HeaderName, StatusCode},
    response::{IntoResponse, Response},
    Json, Router,
};
use serde_json::json;
use sqlx::SqlitePool;

use crate::forwarding::types::ForwardObservation;
use crate::forwarding::target_resolver::TargetResolver;
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
    Router::new().fallback(forward_passthrough).with_state(state)
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
                .into_response()
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
                .into_response()
        }
    };

    let mut upstream = client.request(parts.method, url);

    for (name, value) in &parts.headers {
        if should_forward_request_header(name) {
            upstream = upstream.header(name, value);
        }
    }

    upstream = apply_protocol_auth(upstream, &target.upstream_protocol, &target.api_key, &parts.headers);

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
                .into_response()
        }
    };

    let status = response.status();
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
    )
    .await;
    let headers = response.headers().clone();
    let mut builder = Response::builder().status(status);
    for (name, value) in &headers {
        if should_forward_response_header(name) {
            builder = builder.header(name, value);
        }
    }

    builder
        .body(Body::from_stream(response.bytes_stream()))
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
) {
    let latency_ms = started_at.elapsed().as_millis() as i64;
    let mut observation = ForwardObservation::new(request_id.clone(), gateway_id.to_string());
    observation.provider_id = Some(provider_id.to_string());
    observation.inbound_protocol = Some(inbound_protocol.to_string());
    observation.upstream_protocol = Some(upstream_protocol.to_string());
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
                usage: Default::default(),
            },
            REQUEST_LOG_KEEP,
        )
        .await;
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
        "connection" | "keep-alive" | "proxy-authenticate" | "proxy-authorization" | "te"
            | "trailer" | "transfer-encoding" | "upgrade"
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
            build_upstream_url("https://api.openai.com/v1", "/responses", Some("stream=true")),
            "https://api.openai.com/v1/responses?stream=true"
        );
    }
}
