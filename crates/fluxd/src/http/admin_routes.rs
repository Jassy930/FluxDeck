use std::collections::HashMap;
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

use crate::domain::gateway::{CreateGatewayInput, Gateway, UpdateGatewayInput};
use crate::domain::provider::{CreateProviderInput, Provider, UpdateProviderInput};
use crate::http::dto::BasicOk;
use crate::repo::gateway_repo::GatewayRepo;
use crate::runtime::gateway_manager::GatewayManager;
use crate::service::provider_health_service::ProviderHealthService;
use crate::service::provider_service::DeleteProviderResult;
use crate::service::provider_service::ProviderService;

#[derive(Clone)]
pub struct AdminApiState {
    pool: SqlitePool,
    provider_service: ProviderService,
    provider_health_service: ProviderHealthService,
    gateway_repo: GatewayRepo,
    gateway_manager: Arc<GatewayManager>,
}

impl AdminApiState {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            provider_service: ProviderService::new(pool.clone()),
            provider_health_service: ProviderHealthService::new(pool.clone()),
            gateway_repo: GatewayRepo::new(pool.clone()),
            gateway_manager: Arc::new(GatewayManager::new(pool.clone())),
            pool,
        }
    }

    pub fn gateway_manager(&self) -> Arc<GatewayManager> {
        Arc::clone(&self.gateway_manager)
    }
}

pub fn build_admin_router(state: AdminApiState) -> Router {
    Router::new()
        .route(
            "/admin/providers",
            post(create_provider).get(list_providers),
        )
        .route("/admin/providers/health", get(list_provider_health))
        .route(
            "/admin/providers/{id}",
            put(update_provider).delete(delete_provider),
        )
        .route("/admin/providers/{id}/probe", post(probe_provider))
        .route("/admin/gateways", post(create_gateway).get(list_gateways))
        .route(
            "/admin/gateways/{id}",
            put(update_gateway).delete(delete_gateway),
        )
        .route("/admin/gateways/{id}/start", post(start_gateway))
        .route("/admin/gateways/{id}/stop", post(stop_gateway))
        .route("/admin/logs", get(list_logs))
        .route("/admin/stats/overview", get(get_stats_overview))
        .route("/admin/stats/trend", get(get_stats_trend))
        .with_state(state)
}

async fn create_provider(
    State(state): State<AdminApiState>,
    Json(input): Json<CreateProviderInput>,
) -> (StatusCode, Json<Value>) {
    match state.provider_service.create_provider(input).await {
        Ok(provider) => {
            if let Err(err) = state
                .provider_health_service
                .ensure_provider(&provider.id)
                .await
            {
                return (
                    StatusCode::BAD_REQUEST,
                    Json(json!({
                        "error": err.to_string()
                    })),
                );
            }
            (StatusCode::CREATED, Json(json!(provider)))
        }
        Err(err) => (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "error": err.to_string()
            })),
        ),
    }
}

async fn list_providers(State(state): State<AdminApiState>) -> (StatusCode, Json<Vec<Provider>>) {
    match state.provider_service.list_providers().await {
        Ok(items) => (StatusCode::OK, Json(items)),
        Err(_) => (StatusCode::OK, Json(vec![])),
    }
}

async fn list_provider_health(
    State(state): State<AdminApiState>,
) -> (
    StatusCode,
    Json<Vec<crate::domain::provider_health::ProviderHealthState>>,
) {
    match state.provider_health_service.list_states().await {
        Ok(items) => (StatusCode::OK, Json(items)),
        Err(_) => (StatusCode::OK, Json(vec![])),
    }
}

async fn update_provider(
    State(state): State<AdminApiState>,
    Path(provider_id): Path<String>,
    Json(input): Json<UpdateProviderInput>,
) -> (StatusCode, Json<Value>) {
    match state
        .provider_service
        .update_provider(&provider_id, input)
        .await
    {
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

async fn delete_provider(
    State(state): State<AdminApiState>,
    Path(provider_id): Path<String>,
) -> (StatusCode, Json<Value>) {
    match state.provider_service.delete_provider(&provider_id).await {
        Ok(DeleteProviderResult::Deleted) => (
            StatusCode::OK,
            Json(json!({
                "ok": true,
                "id": provider_id
            })),
        ),
        Ok(DeleteProviderResult::NotFound) => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": "provider not found",
                "id": provider_id
            })),
        ),
        Ok(DeleteProviderResult::ReferencedByGateways(referenced_by_gateway_ids)) => (
            StatusCode::CONFLICT,
            Json(json!({
                "error": "provider is referenced by gateways",
                "id": provider_id,
                "referenced_by_gateway_ids": referenced_by_gateway_ids
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

async fn probe_provider(
    State(state): State<AdminApiState>,
    Path(provider_id): Path<String>,
) -> (StatusCode, Json<Value>) {
    match state
        .provider_health_service
        .probe_provider(&provider_id)
        .await
    {
        Ok(state) => (StatusCode::OK, Json(json!(state))),
        Err(err) => (
            StatusCode::BAD_REQUEST,
            Json(json!({
                "error": err.to_string(),
                "id": provider_id
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
                route_targets: vec![],
                default_model: None,
                enabled: false,
                auto_start: false,
            }),
        ),
    }
}

async fn update_gateway(
    State(state): State<AdminApiState>,
    Path(gateway_id): Path<String>,
    Json(input): Json<UpdateGatewayInput>,
) -> (StatusCode, Json<Value>) {
    let existing_gateway = match state.gateway_repo.get_by_id(&gateway_id).await {
        Ok(Some(gateway)) => gateway,
        Ok(None) => {
            return (
                StatusCode::NOT_FOUND,
                Json(json!({
                    "error": "gateway not found",
                    "id": gateway_id
                })),
            )
        }
        Err(err) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": err.to_string()
                })),
            )
        }
    };

    let was_running = state.gateway_manager.status(&gateway_id).await
        == crate::runtime::gateway_manager::GatewayRuntimeStatus::Running;
    let config_changed = gateway_differs_from_update(&existing_gateway, &input);

    match state.gateway_repo.update(&gateway_id, input).await {
        Ok(Some(gateway)) => {
            let mut restart_performed = false;
            let user_notice = if was_running && config_changed {
                restart_performed = true;
                let restart_result = async {
                    state.gateway_manager.stop_gateway(&gateway_id).await?;
                    state.gateway_manager.start_gateway(&gateway_id).await?;
                    Ok::<(), anyhow::Error>(())
                }
                .await;

                match restart_result {
                    Ok(()) => Some(
                        "Gateway 配置已保存。检测到该实例正在运行且配置发生变化，系统已自动重启以应用变更。"
                            .to_string(),
                    ),
                    Err(err) => Some(format!(
                        "Gateway 配置已保存，但自动重启失败：{err}"
                    )),
                }
            } else if config_changed {
                Some("Gateway 配置已保存。当前实例未运行，因此未触发自动重启。".to_string())
            } else {
                Some("Gateway 配置未发生变化，运行时保持不变。".to_string())
            };

            let runtime_status = state.gateway_manager.status(&gateway_id).await;
            let last_error = state.gateway_manager.last_error(&gateway_id).await;
            (
                StatusCode::OK,
                Json(json!(GatewayUpdateResult {
                    gateway,
                    runtime_status: runtime_status.as_str().to_string(),
                    last_error,
                    restart_performed,
                    config_changed,
                    user_notice,
                })),
            )
        }
        Ok(None) => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": "gateway not found",
                "id": gateway_id
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

async fn delete_gateway(
    State(state): State<AdminApiState>,
    Path(gateway_id): Path<String>,
) -> (StatusCode, Json<Value>) {
    let existing_gateway = match state.gateway_repo.get_by_id(&gateway_id).await {
        Ok(Some(gateway)) => gateway,
        Ok(None) => {
            return (
                StatusCode::NOT_FOUND,
                Json(json!({
                    "error": "gateway not found",
                    "id": gateway_id
                })),
            )
        }
        Err(err) => {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": err.to_string()
                })),
            )
        }
    };

    let runtime_status_before_delete = state.gateway_manager.status(&gateway_id).await;
    let stop_performed = runtime_status_before_delete
        == crate::runtime::gateway_manager::GatewayRuntimeStatus::Running;
    if stop_performed {
        if let Err(err) = state.gateway_manager.stop_gateway(&gateway_id).await {
            return (
                StatusCode::BAD_REQUEST,
                Json(json!({
                    "error": format!("failed to stop running gateway before delete: {err}"),
                    "id": gateway_id
                })),
            );
        }
    }

    match state.gateway_repo.delete(&existing_gateway.id).await {
        Ok(true) => {
            let user_notice = if stop_performed {
                "Gateway 已删除。运行中的实例已先停止。"
            } else {
                "Gateway 已删除。"
            };
            (
                StatusCode::OK,
                Json(json!({
                    "ok": true,
                    "id": existing_gateway.id,
                    "runtime_status_before_delete": runtime_status_before_delete.as_str(),
                    "stop_performed": stop_performed,
                    "user_notice": user_notice
                })),
            )
        }
        Ok(false) => (
            StatusCode::NOT_FOUND,
            Json(json!({
                "error": "gateway not found",
                "id": gateway_id
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

#[derive(Debug, Serialize)]
struct GatewayUpdateResult {
    gateway: Gateway,
    runtime_status: String,
    last_error: Option<String>,
    restart_performed: bool,
    config_changed: bool,
    user_notice: Option<String>,
}

fn gateway_differs_from_update(gateway: &Gateway, input: &UpdateGatewayInput) -> bool {
    gateway.name != input.name
        || gateway.listen_host != input.listen_host
        || gateway.listen_port != input.listen_port
        || gateway.inbound_protocol != input.inbound_protocol
        || gateway.upstream_protocol != input.upstream_protocol
        || gateway.protocol_config_json != input.protocol_config_json
        || gateway.default_provider_id != input.default_provider_id
        || gateway.route_targets
            != crate::repo::gateway_repo::normalized_route_targets(
                &gateway.id,
                &input.default_provider_id,
                &input.route_targets,
            )
        || gateway.default_model != input.default_model
        || gateway.enabled != input.enabled
        || gateway.auto_start != input.auto_start
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
    provider_id_initial: Option<String>,
    model: Option<String>,
    inbound_protocol: Option<String>,
    upstream_protocol: Option<String>,
    model_requested: Option<String>,
    model_effective: Option<String>,
    status_code: i64,
    latency_ms: i64,
    stream: bool,
    first_byte_ms: Option<i64>,
    input_tokens: Option<i64>,
    output_tokens: Option<i64>,
    cached_tokens: Option<i64>,
    total_tokens: Option<i64>,
    usage_json: Option<String>,
    error_stage: Option<String>,
    error_type: Option<String>,
    failover_performed: bool,
    route_attempt_count: i64,
    error: Option<String>,
    created_at: String,
}

#[derive(Debug, Serialize)]
struct LogListResponse {
    items: Vec<LogListItem>,
    next_cursor: Option<LogListCursor>,
    has_more: bool,
}

// Stats API types
#[derive(Debug, Deserialize, Default)]
struct StatsQuery {
    period: Option<String>,
}

#[derive(Debug, Deserialize, Default)]
struct StatsTrendQuery {
    period: Option<String>,
    interval: Option<String>,
}

#[derive(Debug, Serialize)]
struct StatsOverviewResponse {
    total_requests: i64,
    successful_requests: i64,
    error_requests: i64,
    success_rate: f64,
    requests_per_minute: f64,
    total_tokens: i64,
    cached_tokens: i64,
    by_gateway: Vec<DimensionStats>,
    by_provider: Vec<DimensionStats>,
    by_model: Vec<ModelDimensionStats>,
}

#[derive(Debug, Serialize)]
struct DimensionStats {
    #[serde(rename = "gateway_id")]
    _gateway_id: Option<String>,
    #[serde(rename = "provider_id")]
    _provider_id: Option<String>,
    request_count: i64,
    success_count: i64,
    error_count: i64,
    total_tokens: i64,
    cached_tokens: i64,
    avg_latency: i64,
}

#[derive(Debug, Serialize)]
struct ModelDimensionStats {
    model: String,
    request_count: i64,
    success_count: i64,
    error_count: i64,
    total_tokens: i64,
    cached_tokens: i64,
    avg_latency: i64,
}

#[derive(Debug, Serialize)]
struct StatsTrendResponse {
    period: String,
    interval: String,
    data: Vec<StatsTrendPoint>,
}

#[derive(Debug, Serialize)]
struct StatsTrendPoint {
    timestamp: String,
    request_count: i64,
    avg_latency: i64,
    error_count: i64,
    input_tokens: i64,
    output_tokens: i64,
    cached_tokens: i64,
    by_model: Vec<StatsTrendModelPoint>,
}

#[derive(Debug, Serialize)]
struct StatsTrendModelPoint {
    model: String,
    total_tokens: i64,
    input_tokens: i64,
    output_tokens: i64,
    cached_tokens: i64,
    request_count: i64,
    error_count: i64,
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
        "SELECT request_id, gateway_id, provider_id, provider_id_initial, model, inbound_protocol, upstream_protocol, model_requested, model_effective, status_code, latency_ms, stream, first_byte_ms, input_tokens, output_tokens, cached_tokens, total_tokens, usage_json, error_stage, error_type, failover_performed, route_attempt_count, error, created_at FROM request_logs",
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
        builder
            .push("(status_code >= ")
            .push_bind(400_i64)
            .push(" OR error IS NOT NULL)");
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
            provider_id_initial: row.get::<Option<String>, _>("provider_id_initial"),
            model: row.get::<Option<String>, _>("model"),
            inbound_protocol: row.get::<Option<String>, _>("inbound_protocol"),
            upstream_protocol: row.get::<Option<String>, _>("upstream_protocol"),
            model_requested: row.get::<Option<String>, _>("model_requested"),
            model_effective: row.get::<Option<String>, _>("model_effective"),
            status_code: row.get::<i64, _>("status_code"),
            latency_ms: row.get::<i64, _>("latency_ms"),
            stream: row.get::<i64, _>("stream") != 0,
            first_byte_ms: row.get::<Option<i64>, _>("first_byte_ms"),
            input_tokens: row.get::<Option<i64>, _>("input_tokens"),
            output_tokens: row.get::<Option<i64>, _>("output_tokens"),
            cached_tokens: row.get::<Option<i64>, _>("cached_tokens"),
            total_tokens: row.get::<Option<i64>, _>("total_tokens"),
            usage_json: row.get::<Option<String>, _>("usage_json"),
            error_stage: row.get::<Option<String>, _>("error_stage"),
            error_type: row.get::<Option<String>, _>("error_type"),
            failover_performed: row.get::<i64, _>("failover_performed") != 0,
            route_attempt_count: row.get::<i64, _>("route_attempt_count"),
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

/// Parse period string like "1h", "6h", "24h", "1d", "7d" into hours
fn parse_period_to_hours(period: &str) -> i64 {
    let period = period.trim();
    if period.is_empty() {
        return 1; // default 1 hour
    }

    let num_part: String = period.chars().take_while(|c| c.is_ascii_digit()).collect();
    let unit_part: String = period.chars().skip_while(|c| c.is_ascii_digit()).collect();

    let num: i64 = num_part.parse().unwrap_or(1);

    match unit_part.to_lowercase().as_str() {
        "m" | "min" | "minute" | "minutes" => num / 60, // convert minutes to hours
        "h" | "hour" | "hours" => num,
        "d" | "day" | "days" => num * 24,
        "w" | "week" | "weeks" => num * 24 * 7,
        _ => 1, // default 1 hour
    }
}

/// Parse interval string like "1m", "5m", "15m", "1h" into minutes
fn parse_interval_to_minutes(interval: &str) -> i64 {
    let interval = interval.trim();
    if interval.is_empty() {
        return 5; // default 5 minutes
    }

    let num_part: String = interval
        .chars()
        .take_while(|c| c.is_ascii_digit())
        .collect();
    let unit_part: String = interval
        .chars()
        .skip_while(|c| c.is_ascii_digit())
        .collect();

    let num: i64 = num_part.parse().unwrap_or(5);

    match unit_part.to_lowercase().as_str() {
        "s" | "sec" | "second" | "seconds" => num / 60,
        "m" | "min" | "minute" | "minutes" => num,
        "h" | "hour" | "hours" => num * 60,
        _ => 5,
    }
}

async fn get_stats_overview(
    State(state): State<AdminApiState>,
    Query(query): Query<StatsQuery>,
) -> (StatusCode, Json<StatsOverviewResponse>) {
    let period = query.period.as_deref().unwrap_or("1h");
    let hours = parse_period_to_hours(period);

    // Calculate time range
    let since = match sqlx::query_scalar::<_, String>(&format!(
        "SELECT datetime('now', '-{} hours')",
        hours
    ))
    .fetch_one(&state.pool)
    .await
    {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::OK,
                Json(StatsOverviewResponse {
                    total_requests: 0,
                    successful_requests: 0,
                    error_requests: 0,
                    success_rate: 0.0,
                    requests_per_minute: 0.0,
                    total_tokens: 0,
                    cached_tokens: 0,
                    by_gateway: vec![],
                    by_provider: vec![],
                    by_model: vec![],
                }),
            );
        }
    };

    // Get total stats
    let total_stats = sqlx::query_as::<_, (i64, i64, i64, i64, i64)>(
        "SELECT
            COUNT(*) as total_requests,
            SUM(CASE WHEN status_code < 400 AND error IS NULL THEN 1 ELSE 0 END) as successful_requests,
            SUM(CASE WHEN status_code >= 400 OR error IS NOT NULL THEN 1 ELSE 0 END) as error_requests,
            COALESCE(SUM(total_tokens), 0) as total_tokens,
            COALESCE(SUM(cached_tokens), 0) as cached_tokens
         FROM request_logs
         WHERE created_at >= ?",
    )
    .bind(&since)
    .fetch_one(&state.pool)
    .await;

    let (total_requests, successful_requests, error_requests, total_tokens, cached_tokens) =
        match total_stats {
            Ok(row) => row,
            Err(_) => (0, 0, 0, 0, 0),
        };

    let success_rate = if total_requests > 0 {
        (successful_requests as f64 / total_requests as f64) * 100.0
    } else {
        0.0
    };

    let requests_per_minute = if hours > 0 {
        total_requests as f64 / (hours as f64 * 60.0)
    } else {
        0.0
    };

    // Get stats by gateway
    let by_gateway = sqlx::query_as::<_, (String, i64, i64, i64, i64, i64, i64)>(
        "SELECT
            gateway_id,
            COUNT(*) as request_count,
            SUM(CASE WHEN status_code < 400 AND error IS NULL THEN 1 ELSE 0 END) as success_count,
            SUM(CASE WHEN status_code >= 400 OR error IS NOT NULL THEN 1 ELSE 0 END) as error_count,
            COALESCE(SUM(total_tokens), 0) as total_tokens,
            COALESCE(SUM(cached_tokens), 0) as cached_tokens,
            CAST(ROUND(COALESCE(AVG(latency_ms), 0)) AS INTEGER) as avg_latency
         FROM request_logs
         WHERE created_at >= ?
         GROUP BY gateway_id
         ORDER BY request_count DESC",
    )
    .bind(&since)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default()
    .into_iter()
    .map(
        |(
            gateway_id,
            request_count,
            success_count,
            error_count,
            total_tokens,
            cached_tokens,
            avg_latency,
        )| {
            DimensionStats {
                _gateway_id: Some(gateway_id),
                _provider_id: None,
                request_count,
                success_count,
                error_count,
                total_tokens,
                cached_tokens,
                avg_latency,
            }
        },
    )
    .collect();

    // Get stats by provider
    let by_provider = sqlx::query_as::<_, (String, i64, i64, i64, i64, i64, i64)>(
        "SELECT
            provider_id,
            COUNT(*) as request_count,
            SUM(CASE WHEN status_code < 400 AND error IS NULL THEN 1 ELSE 0 END) as success_count,
            SUM(CASE WHEN status_code >= 400 OR error IS NOT NULL THEN 1 ELSE 0 END) as error_count,
            COALESCE(SUM(total_tokens), 0) as total_tokens,
            COALESCE(SUM(cached_tokens), 0) as cached_tokens,
            CAST(ROUND(COALESCE(AVG(latency_ms), 0)) AS INTEGER) as avg_latency
         FROM request_logs
         WHERE created_at >= ?
         GROUP BY provider_id
         ORDER BY request_count DESC",
    )
    .bind(&since)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default()
    .into_iter()
    .map(
        |(
            provider_id,
            request_count,
            success_count,
            error_count,
            total_tokens,
            cached_tokens,
            avg_latency,
        )| {
            DimensionStats {
                _gateway_id: None,
                _provider_id: Some(provider_id),
                request_count,
                success_count,
                error_count,
                total_tokens,
                cached_tokens,
                avg_latency,
            }
        },
    )
    .collect();

    // Get stats by model
    let by_model = sqlx::query_as::<_, (Option<String>, i64, i64, i64, i64, i64, i64)>(
        "SELECT
            model_effective,
            COUNT(*) as request_count,
            SUM(CASE WHEN status_code < 400 AND error IS NULL THEN 1 ELSE 0 END) as success_count,
            SUM(CASE WHEN status_code >= 400 OR error IS NOT NULL THEN 1 ELSE 0 END) as error_count,
            COALESCE(SUM(total_tokens), 0) as total_tokens,
            COALESCE(SUM(cached_tokens), 0) as cached_tokens,
            CAST(ROUND(COALESCE(AVG(latency_ms), 0)) AS INTEGER) as avg_latency
         FROM request_logs
         WHERE created_at >= ?
         GROUP BY model_effective
         ORDER BY request_count DESC",
    )
    .bind(&since)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default()
    .into_iter()
    .filter_map(
        |(
            model,
            request_count,
            success_count,
            error_count,
            total_tokens,
            cached_tokens,
            avg_latency,
        )| {
            model.map(|m| ModelDimensionStats {
                model: m,
                request_count,
                success_count,
                error_count,
                total_tokens,
                cached_tokens,
                avg_latency,
            })
        },
    )
    .collect();

    (
        StatusCode::OK,
        Json(StatsOverviewResponse {
            total_requests,
            successful_requests,
            error_requests,
            success_rate,
            requests_per_minute,
            total_tokens,
            cached_tokens,
            by_gateway,
            by_provider,
            by_model,
        }),
    )
}

async fn get_stats_trend(
    State(state): State<AdminApiState>,
    Query(query): Query<StatsTrendQuery>,
) -> (StatusCode, Json<StatsTrendResponse>) {
    let period = query.period.as_deref().unwrap_or("1h");
    let interval = query.interval.as_deref().unwrap_or("5m");

    let hours = parse_period_to_hours(period);
    let interval_minutes = parse_interval_to_minutes(interval);

    // Generate time buckets
    // SQLite doesn't have a generate_series, so we'll query raw data and aggregate in memory
    // First, get the time range
    let since = match sqlx::query_scalar::<_, String>(&format!(
        "SELECT datetime('now', '-{} hours')",
        hours
    ))
    .fetch_one(&state.pool)
    .await
    {
        Ok(t) => t,
        Err(_) => {
            return (
                StatusCode::OK,
                Json(StatsTrendResponse {
                    period: period.to_string(),
                    interval: interval.to_string(),
                    data: vec![],
                }),
            );
        }
    };

    // Query aggregated by time buckets using strftime
    let interval_seconds = interval_minutes * 60;
    let bucket_expr = format!(
        "datetime((strftime('%s', created_at) / {}) * {}, 'unixepoch')",
        interval_seconds, interval_seconds
    );
    let normalized_model_expr = "COALESCE(NULLIF(TRIM(COALESCE(model_effective, '')), ''), NULLIF(TRIM(COALESCE(model, '')), ''), 'Unknown model')";

    let rows = sqlx::query_as::<_, (String, i64, i64, i64, i64, i64, i64)>(
        &format!(
            "SELECT
                {} as time_bucket,
                COUNT(*) as request_count,
                CAST(ROUND(COALESCE(AVG(latency_ms), 0)) AS INTEGER) as avg_latency,
                SUM(CASE WHEN status_code >= 400 OR error IS NOT NULL THEN 1 ELSE 0 END) as error_count,
                COALESCE(SUM(input_tokens), 0) as input_tokens,
                COALESCE(SUM(output_tokens), 0) as output_tokens,
                COALESCE(SUM(cached_tokens), 0) as cached_tokens
             FROM request_logs
             WHERE created_at >= ?
             GROUP BY time_bucket
             ORDER BY time_bucket ASC",
            bucket_expr
        ),
    )
    .bind(&since)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let model_rows = sqlx::query_as::<_, (String, String, i64, i64, i64, i64, i64, i64)>(
        &format!(
            "SELECT
                {} as time_bucket,
                {} as model,
                COALESCE(SUM(total_tokens), 0) as total_tokens,
                COALESCE(SUM(input_tokens), 0) as input_tokens,
                COALESCE(SUM(output_tokens), 0) as output_tokens,
                COALESCE(SUM(cached_tokens), 0) as cached_tokens,
                COUNT(*) as request_count,
                SUM(CASE WHEN status_code >= 400 OR error IS NOT NULL THEN 1 ELSE 0 END) as error_count
             FROM request_logs
             WHERE created_at >= ?
             GROUP BY time_bucket, model
             ORDER BY time_bucket ASC, total_tokens DESC, model ASC",
            bucket_expr, normalized_model_expr
        ),
    )
    .bind(&since)
    .fetch_all(&state.pool)
    .await
    .unwrap_or_default();

    let mut models_by_bucket: HashMap<String, Vec<StatsTrendModelPoint>> = HashMap::new();
    for (
        timestamp,
        model,
        total_tokens,
        input_tokens,
        output_tokens,
        cached_tokens,
        request_count,
        error_count,
    ) in model_rows
    {
        models_by_bucket
            .entry(timestamp)
            .or_default()
            .push(StatsTrendModelPoint {
                model,
                total_tokens,
                input_tokens,
                output_tokens,
                cached_tokens,
                request_count,
                error_count,
            });
    }

    let data = rows
        .into_iter()
        .map(
            |(
                timestamp,
                request_count,
                avg_latency,
                error_count,
                input_tokens,
                output_tokens,
                cached_tokens,
            )| {
                let by_model = models_by_bucket.remove(&timestamp).unwrap_or_default();
                StatsTrendPoint {
                    timestamp,
                    request_count,
                    avg_latency,
                    error_count,
                    input_tokens,
                    output_tokens,
                    cached_tokens,
                    by_model,
                }
            },
        )
        .collect();

    (
        StatusCode::OK,
        Json(StatsTrendResponse {
            period: period.to_string(),
            interval: interval.to_string(),
            data,
        }),
    )
}
