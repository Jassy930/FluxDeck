use axum::{
    extract::{Json, State},
    http::StatusCode,
    routing::post,
    Router,
};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

use crate::upstream::openai_client::OpenAiClient;

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
    match fetch_provider_and_forward(&state, payload).await {
        Ok((status, value)) => (status, Json(value)),
        Err(err) => (
            StatusCode::BAD_GATEWAY,
            Json(json!({
                "error": {
                    "message": format!("upstream forward failed: {err}"),
                    "type": "upstream_error"
                }
            })),
        ),
    }
}

async fn fetch_provider_and_forward(
    state: &OpenAiRouteState,
    payload: Value,
) -> anyhow::Result<(StatusCode, Value)> {
    let row = sqlx::query(
        r#"
        SELECT p.base_url, p.api_key
        FROM gateways g
        JOIN providers p ON p.id = g.default_provider_id
        WHERE g.id = ?1
        "#,
    )
    .bind(&state.gateway_id)
    .fetch_optional(&state.pool)
    .await?;

    let row = row.ok_or_else(|| anyhow::anyhow!("gateway not found: {}", state.gateway_id))?;

    let base_url: String = row.get("base_url");
    let api_key: String = row.get("api_key");

    state
        .client
        .chat_completions(&base_url, &api_key, &payload)
        .await
        .map(|(status, value)| (StatusCode::from_u16(status.as_u16()).unwrap_or(StatusCode::BAD_GATEWAY), value))
}
