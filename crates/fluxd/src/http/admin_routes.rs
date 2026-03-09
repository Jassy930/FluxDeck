use std::sync::Arc;

use axum::{
    extract::{Path, Query, State},
    http::StatusCode,
    routing::{get, post, put},
    Json, Router,
};
use serde::{Deserialize, Serialize};
use serde_json::{json, Value};
use sqlx::{QueryBuilder, Row, Sqlite, SqlitePool};

use crate::domain::gateway::{CreateGatewayInput, Gateway};
use crate::domain::provider::{CreateProviderInput, Provider, UpdateProviderInput};
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
        .route("/admin/providers/{id}", put(update_provider))
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

async fn update_provider(
    State(state): State<AdminApiState>,
    Path(provider_id): Path<String>,
    Json(input): Json<UpdateProviderInput>,
) -> (StatusCode, Json<Value>) {
    match state.provider_service.update_provider(&provider_id, input).await {
        Ok(Some(provider)) => (StatusCode::OK, Json(json!(provider))),
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": "provider not found",
                "id": provider_id
            })),
        ),
        Err(err) => (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "error": err.to_string()
            })),
        ),
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
                upstream_protocol: "provider_default".to_string(),
                protocol_config_json: json!({}),
                default_provider_id: String::new(),
                default_model: None,
                enabled: false,
            }),
        ),
    }
}

async fn list_gateways(
    State(state): State<AdminApiState>,
) -> (StatusCode, Json<Vec<GatewayWithRuntime>>) {
    match state.gateway_repo.list().await {
        Ok(items) => {
            let mut gateways = Vec::with_capacity(items.len());
            for gateway in items {
                let runtime_status = state.gateway_manager.status(&gateway.id).await;
                let last_error = state.gateway_manager.last_error(&gateway.id).await;
                gateways.push(GatewayWithRuntime {
                    gateway,
                    runtime_status: runtime_status.as_str().to_string(),
                    last_error,
                });
            }
            (StatusCode::OK, Json(gateways))
        }
        Err(_) => (StatusCode::OK, Json(vec![])),
    }
}

#[derive(Debug, Serialize)]
struct GatewayWithRuntime {
    #[serde(flatten)]
    gateway: Gateway,
    runtime_status: String,
    last_error: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct LogListQuery {
    limit: Option<usize>,
    cursor_created_at: Option<String>,
    cursor_request_id: Option<String>,
    gateway_id: Option<String>,
    provider_id: Option<String>,
    status_code: Option<i64>,
    errors_only: Option<bool>,
}

#[derive(Debug, Serialize)]
struct LogListCursor {
    created_at: String,
    request_id: String,
}

#[derive(Debug, Serialize)]
struct LogListItem {
    request_id: String,
    gateway_id: String,
    provider_id: String,
    model: Option<String>,
    status_code: i64,
    latency_ms: i64,
    error: Option<String>,
    created_at: String,
}

#[derive(Debug, Serialize)]
struct LogListResponse {
    items: Vec<LogListItem>,
    next_cursor: Option<LogListCursor>,
    has_more: bool,
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

async fn list_logs(
    State(state): State<AdminApiState>,
    Query(query): Query<LogListQuery>,
) -> (StatusCode, Json<LogListResponse>) {
    let limit = query.limit.unwrap_or(50).clamp(1, 100);

    let mut builder = QueryBuilder::<Sqlite>::new(
        "SELECT request_id, gateway_id, provider_id, model, status_code, latency_ms, error, created_at FROM request_logs",
    );

    let mut has_where = false;

    if let (Some(cursor_created_at), Some(cursor_request_id)) = (
        query.cursor_created_at.as_deref(),
        query.cursor_request_id.as_deref(),
    ) {
        builder.push(if has_where { " AND " } else { " WHERE " });
        has_where = true;
        builder
            .push("(created_at < ")
            .push_bind(cursor_created_at)
            .push(" OR (created_at = ")
            .push_bind(cursor_created_at)
            .push(" AND request_id < ")
            .push_bind(cursor_request_id)
            .push("))");
    }

    if let Some(gateway_id) = query.gateway_id.as_deref() {
        builder.push(if has_where { " AND " } else { " WHERE " });
        has_where = true;
        builder.push("gateway_id = ").push_bind(gateway_id);
    }

    if let Some(provider_id) = query.provider_id.as_deref() {
        builder.push(if has_where { " AND " } else { " WHERE " });
        has_where = true;
        builder.push("provider_id = ").push_bind(provider_id);
    }

    if let Some(status_code) = query.status_code {
        builder.push(if has_where { " AND " } else { " WHERE " });
        has_where = true;
        builder.push("status_code = ").push_bind(status_code);
    }

    if query.errors_only.unwrap_or(false) {
        builder.push(if has_where { " AND " } else { " WHERE " });
        builder.push("(status_code >= ").push_bind(400_i64).push(" OR error IS NOT NULL)");
    }

    builder
        .push(" ORDER BY created_at DESC, request_id DESC LIMIT ")
        .push_bind((limit + 1) as i64);

    let rows = builder.build().fetch_all(&state.pool).await;

    let Ok(rows) = rows else {
        return (
            StatusCode::OK,
            Json(LogListResponse {
                items: vec![],
                next_cursor: None,
                has_more: false,
            }),
        );
    };

    let mut items = rows
        .into_iter()
        .map(|row| LogListItem {
            request_id: row.get::<String, _>("request_id"),
            gateway_id: row.get::<String, _>("gateway_id"),
            provider_id: row.get::<String, _>("provider_id"),
            model: row.get::<Option<String>, _>("model"),
            status_code: row.get::<i64, _>("status_code"),
            latency_ms: row.get::<i64, _>("latency_ms"),
            error: row.get::<Option<String>, _>("error"),
            created_at: row.get::<String, _>("created_at"),
        })
        .collect::<Vec<_>>();

    let has_more = items.len() > limit;
    if has_more {
        items.truncate(limit);
    }

    let next_cursor = if has_more {
        items.last().map(|item| LogListCursor {
            created_at: item.created_at.clone(),
            request_id: item.request_id.clone(),
        })
    } else {
        None
    };

    (
        StatusCode::OK,
        Json(LogListResponse {
            items,
            next_cursor,
            has_more,
        }),
    )
}
