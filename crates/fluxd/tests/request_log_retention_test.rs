use fluxd::service::request_log_service::{RequestLogEntry, RequestLogService};
use fluxd::storage::migrate::run_migrations;
use serde_json::json;

#[tokio::test]
async fn trims_old_logs_by_count_limit() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let service = RequestLogService::new(pool.clone());

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_1")
    .bind("Provider 1")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        "INSERT INTO gateways (id, name, listen_host, listen_port, inbound_protocol, default_provider_id, default_model, enabled) VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, 1)",
    )
    .bind("gw_1")
    .bind("Gateway 1")
    .bind("127.0.0.1")
    .bind(19991_i64)
    .bind("openai")
    .bind("provider_1")
    .bind("gpt-4o-mini")
    .execute(&pool)
    .await
    .expect("insert gateway");

    for idx in 0..7_i64 {
        service
            .append_and_trim_with_dimensions(
                RequestLogEntry {
                    request_id: format!("req_{idx}"),
                    gateway_id: "gw_1".to_string(),
                    provider_id: "provider_1".to_string(),
                    model: Some("gpt-4o-mini".to_string()),
                    status_code: 200,
                    latency_ms: 30 + idx,
                    error: None,
                },
                5,
                &json!({
                    "compatibility_mode": "compatible",
                    "event": "degraded_to_estimate"
                }),
            )
            .await
            .expect("append and trim");
    }

    let rows: Vec<(String, Option<String>)> = sqlx::query_as(
        "SELECT request_id, error FROM request_logs ORDER BY rowid ASC",
    )
    .fetch_all(&pool)
    .await
    .expect("select logs");

    let ids: Vec<String> = rows.iter().map(|item| item.0.clone()).collect();
    assert_eq!(ids, vec!["req_2", "req_3", "req_4", "req_5", "req_6"]);
    for (_, error) in rows {
        let text = error.expect("log error contains dimensions");
        assert!(text.contains("compatibility_mode"));
    }
}
