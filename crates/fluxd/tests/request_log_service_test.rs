use fluxd::forwarding::types::{ForwardObservation, UsageSnapshot};
use fluxd::service::request_log_service::{RequestLogEntry, RequestLogService};
use fluxd::storage::migrate::run_migrations;
use serde_json::json;

#[tokio::test]
async fn request_logs_persist_forwarding_observation_fields() {
    let pool = setup_db().await;
    append_test_log(&pool).await;

    let row = fetch_latest_log(&pool).await;
    assert_eq!(row.model_requested.as_deref(), Some("claude-3-7-sonnet"));
    assert_eq!(row.model_effective.as_deref(), Some("claude-sonnet-4-5"));
    assert_eq!(row.input_tokens, Some(128));
    assert_eq!(row.cached_tokens, Some(64));
    assert_eq!(row.provider_id_initial.as_deref(), Some("provider_req_log"));
    assert_eq!(row.route_attempt_count, 2);
    assert!(row.failover_performed);
}

struct StoredRequestLogRow {
    model_requested: Option<String>,
    model_effective: Option<String>,
    input_tokens: Option<i64>,
    cached_tokens: Option<i64>,
    provider_id_initial: Option<String>,
    route_attempt_count: i64,
    failover_performed: bool,
}

async fn setup_db() -> sqlx::SqlitePool {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_req_log")
    .bind("Provider Req Log")
    .bind("anthropic")
    .bind("https://api.anthropic.com/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, upstream_protocol, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, 1)",
    )
    .bind("gw_req_log")
    .bind("Gateway Req Log")
    .bind("127.0.0.1")
    .bind(18082_i64)
    .bind("anthropic")
    .bind("anthropic")
    .bind("provider_req_log")
    .bind("claude-sonnet-4-5")
    .execute(&pool)
    .await
    .expect("insert gateway");

    pool
}

async fn append_test_log(pool: &sqlx::SqlitePool) {
    let service = RequestLogService::new(pool.clone());
    let mut observation = ForwardObservation::new("req_forward_obs", "gw_req_log");
    observation.provider_id = Some("provider_req_log".to_string());
    observation.provider_id_initial = Some("provider_req_log".to_string());
    observation.inbound_protocol = Some("anthropic".to_string());
    observation.upstream_protocol = Some("anthropic".to_string());
    observation.model_requested = Some("claude-3-7-sonnet".to_string());
    observation.model_effective = Some("claude-sonnet-4-5".to_string());
    observation.route_attempt_count = 2;
    observation.failover_performed = true;
    observation.status_code = Some(200);
    observation.latency_ms = Some(84);
    observation.first_byte_ms = Some(21);

    let usage = UsageSnapshot {
        input_tokens: Some(128),
        output_tokens: Some(256),
        cached_tokens: Some(64),
        total_tokens: Some(384),
        usage_json: Some(
            json!({"input_tokens": 128, "output_tokens": 256, "cache_read_input_tokens": 64}),
        ),
    };

    service
        .append_and_trim(
            RequestLogEntry {
                request_id: "req_forward_obs".to_string(),
                gateway_id: "gw_req_log".to_string(),
                provider_id: "provider_req_log".to_string(),
                model: Some("claude-sonnet-4-5".to_string()),
                status_code: 200,
                latency_ms: 84,
                error: None,
                observation,
                usage,
            },
            10,
        )
        .await
        .expect("append request log");
}

async fn fetch_latest_log(pool: &sqlx::SqlitePool) -> StoredRequestLogRow {
    let row = sqlx::query_as::<
        _,
        (
            Option<String>,
            Option<String>,
            Option<i64>,
            Option<i64>,
            Option<String>,
            i64,
            i64,
        ),
    >(
        "SELECT model_requested, model_effective, input_tokens, cached_tokens, provider_id_initial, route_attempt_count, failover_performed FROM request_logs WHERE request_id = ?1",
    )
    .bind("req_forward_obs")
    .fetch_one(pool)
    .await
    .expect("fetch latest request log");

    StoredRequestLogRow {
        model_requested: row.0,
        model_effective: row.1,
        input_tokens: row.2,
        cached_tokens: row.3,
        provider_id_initial: row.4,
        route_attempt_count: row.5,
        failover_performed: row.6 != 0,
    }
}
