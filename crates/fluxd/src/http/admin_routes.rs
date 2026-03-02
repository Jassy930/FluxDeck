use std::sync::Arc;

use axum::{
    extract::{Path, State},
    http::StatusCode,
    routing::{get, post},
    Json, Router,
};
use serde_json::{json, Value};
use sqlx::{Row, SqlitePool};

use crate::domain::gateway::{CreateGatewayInput, Gateway};
use crate::domain::provider::{CreateProviderInput, Provider};
use crate::http::dto::BasicOk;
use crate::repo::gateway_repo::GatewayRepo;
use crate::runtime::gateway_manager::GatewayManager;
use crate::service::provider_service::ProviderService;

#[derive(Clone)]
pub struct AdminApiState {
    pool: SqlitePool,
    provider_service: ProviderService,
    gateway_repo: GatewayRepo,
    gateway_manager: Arc<GatewayManager>,
}

impl AdminApiState {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            provider_service: ProviderService::new(pool.clone()),
            gateway_repo: GatewayRepo::new(pool.clone()),
            gateway_manager: Arc::new(GatewayManager::new(pool.clone())),
            pool,
        }
    }
}

pub fn build_admin_router(state: AdminApiState) -> Router {
    Router::new()
        .route("/admin/providers", post(create_provider).get(list_providers))
        .route("/admin/gateways", post(create_gateway).get(list_gateways))
        .route("/admin/gateways/{id}/start", post(start_gateway))
        .route("/admin/gateways/{id}/stop", post(stop_gateway))
        .route("/admin/logs", get(list_logs))
        .with_state(state)
}

async fn create_provider(
    State(state): State<AdminApiState>,
    Json(input): Json<CreateProviderInput>,
) -> (StatusCode, Json<Provider>) {
    match state.provider_service.create_provider(input).await {
        Ok(provider) => (StatusCode::CREATED, Json(provider)),
        Err(err) => (
            StatusCode::BAD_REQUEST,
            Json(Provider {
                id: format!("error:{err}"),
                name: String::new(),
                kind: String::new(),
                base_url: String::new(),
                api_key: String::new(),
                models: vec![],
                enabled: false,
            }),
        ),
    }
}

async fn list_providers(State(state): State<AdminApiState>) -> (StatusCode, Json<Vec<Provider>>) {
    match state.provider_service.list_providers().await {
        Ok(items) => (StatusCode::OK, Json(items)),
        Err(_) => (StatusCode::OK, Json(vec![])),
    }
}

async fn create_gateway(
    State(state): State<AdminApiState>,
    Json(input): Json<CreateGatewayInput>,
) -> (StatusCode, Json<Gateway>) {
    match state.gateway_repo.create(input).await {
        Ok(gateway) => (StatusCode::CREATED, Json(gateway)),
        Err(err) => (
            StatusCode::BAD_REQUEST,
            Json(Gateway {
                id: format!("error:{err}"),
                name: String::new(),
                listen_host: String::new(),
                listen_port: 0,
                inbound_protocol: String::new(),
                default_provider_id: String::new(),
                default_model: None,
                enabled: false,
            }),
        ),
    }
}

async fn list_gateways(State(state): State<AdminApiState>) -> (StatusCode, Json<Vec<Gateway>>) {
    match state.gateway_repo.list().await {
        Ok(items) => (StatusCode::OK, Json(items)),
        Err(_) => (StatusCode::OK, Json(vec![])),
    }
}

async fn start_gateway(
    State(state): State<AdminApiState>,
    Path(gateway_id): Path<String>,
) -> (StatusCode, Json<BasicOk>) {
    match state.gateway_manager.start_gateway(&gateway_id).await {
        Ok(_) => (StatusCode::OK, Json(BasicOk::new())),
        Err(_) => (StatusCode::BAD_REQUEST, Json(BasicOk { ok: false })),
    }
}

async fn stop_gateway(
    State(state): State<AdminApiState>,
    Path(gateway_id): Path<String>,
) -> (StatusCode, Json<BasicOk>) {
    match state.gateway_manager.stop_gateway(&gateway_id).await {
        Ok(_) => (StatusCode::OK, Json(BasicOk::new())),
        Err(_) => (StatusCode::BAD_REQUEST, Json(BasicOk { ok: false })),
    }
}

async fn list_logs(State(state): State<AdminApiState>) -> (StatusCode, Json<Vec<Value>>) {
    let rows = sqlx::query(
        r#"
        SELECT request_id, gateway_id, provider_id, model, status_code, latency_ms, error, created_at
        FROM request_logs
        ORDER BY created_at DESC
        LIMIT 200
        "#,
    )
    .fetch_all(&state.pool)
    .await;

    let Ok(rows) = rows else {
        return (StatusCode::OK, Json(vec![]));
    };

    let logs = rows
        .into_iter()
        .map(|row| {
            json!({
                "request_id": row.get::<String, _>("request_id"),
                "gateway_id": row.get::<String, _>("gateway_id"),
                "provider_id": row.get::<String, _>("provider_id"),
                "model": row.get::<Option<String>, _>("model"),
                "status_code": row.get::<i64, _>("status_code"),
                "latency_ms": row.get::<i64, _>("latency_ms"),
                "error": row.get::<Option<String>, _>("error"),
                "created_at": row.get::<String, _>("created_at")
            })
        })
        .collect();

    (StatusCode::OK, Json(logs))
}
