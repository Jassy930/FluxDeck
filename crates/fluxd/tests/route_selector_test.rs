use fluxd::forwarding::route_selector::RouteSelector;
use fluxd::storage::migrate::run_migrations;
use serde_json::json;

#[tokio::test]
async fn route_selector_skips_unhealthy_provider_and_uses_next_target() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        r#"
        INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
    )
    .bind("provider_primary")
    .bind("Provider Primary")
    .bind("openai")
    .bind("https://primary.example/v1")
    .bind("sk-primary")
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert primary provider");

    sqlx::query(
        r#"
        INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
    )
    .bind("provider_backup")
    .bind("Provider Backup")
    .bind("openai")
    .bind("https://backup.example/v1")
    .bind("sk-backup")
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert backup provider");

    sqlx::query(
        r#"
        INSERT INTO gateways (
            id, name, listen_host, listen_port, inbound_protocol,
            upstream_protocol, protocol_config_json, default_provider_id,
            default_model, enabled, auto_start
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
        "#,
    )
    .bind("gw_route_selector")
    .bind("Gateway Route Selector")
    .bind("127.0.0.1")
    .bind(18081_i64)
    .bind("openai")
    .bind("provider_default")
    .bind(json!({"compatibility_mode": "compatible"}).to_string())
    .bind("provider_primary")
    .bind("gpt-4o-mini")
    .bind(1_i64)
    .bind(0_i64)
    .execute(&pool)
    .await
    .expect("insert gateway");

    sqlx::query(
        r#"
        UPDATE gateway_route_targets
        SET provider_id = ?2
        WHERE gateway_id = ?1 AND priority = 0
        "#,
    )
    .bind("gw_route_selector")
    .bind("provider_primary")
    .execute(&pool)
    .await
    .expect("set primary route target");

    sqlx::query(
        r#"
        INSERT INTO gateway_route_targets (id, gateway_id, provider_id, priority, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5)
        "#,
    )
    .bind("gw_route_selector__route__1")
    .bind("gw_route_selector")
    .bind("provider_backup")
    .bind(1_i64)
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert backup route target");

    sqlx::query(
        r#"
        INSERT INTO provider_health_states (
            provider_id, scope, status, failure_streak, success_streak, circuit_open_until
        )
        VALUES (?1, 'global', 'unhealthy', 3, 0, '9999999999')
        "#,
    )
    .bind("provider_primary")
    .execute(&pool)
    .await
    .expect("mark primary unhealthy");

    let selector = RouteSelector::new(pool);
    let target = selector
        .select("gw_route_selector")
        .await
        .expect("select route target");

    assert_eq!(target.provider_id, "provider_backup");
    assert_eq!(target.base_url, "https://backup.example/v1");
}
