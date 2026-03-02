use std::time::{Instant, SystemTime, UNIX_EPOCH};

use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::post,
    Router,
};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

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
) -> (StatusCode, Json<Value>) {
    let request_id = next_request_id();
    let model = payload
        .get("model")
        .and_then(Value::as_str)
        .map(ToOwned::to_owned);
    let started_at = Instant::now();
    let log_service = RequestLogService::new(state.pool.clone());

    match fetch_provider_target(&state).await {
        Ok(target) => {
            let response = state
                .client
                .chat_completions(&target.base_url, &target.api_key, &payload)
                .await;

            match response {
                Ok((status, value)) => {
                    let status_code =
                        StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY);

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

                    (status_code, Json(value))
                }
                Err(err) => {
                    append_log(
                        &log_service,
                        RequestLogEntry {
                            request_id: request_id.clone(),
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
                        Json(json!({
                            "error": {
                                "message": format!("upstream forward failed: {err}"),
                                "type": "upstream_error",
                                "request_id": request_id
                            }
                        })),
                    )
                }
            }
        }
        Err(err) => {
            append_log(
                &log_service,
                RequestLogEntry {
                    request_id: request_id.clone(),
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
                Json(json!({
                    "error": {
                        "message": format!("invalid gateway/provider state: {err}"),
                        "type": "config_error",
                        "request_id": request_id
                    }
                })),
            )
        }
    }
}

#[derive(Debug)]
struct ProviderRoutingTarget {
    provider_id: String,
    base_url: String,
    api_key: String,
}

async fn fetch_provider_target(state: &OpenAiRouteState) -> anyhow::Result<ProviderRoutingTarget> {
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
