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

#[tokio::test]
async fn route_selector_prefers_healthy_provider_over_higher_priority_degraded_target() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    insert_provider(&pool, "provider_primary", "https://primary.example/v1").await;
    insert_provider(&pool, "provider_backup", "https://backup.example/v1").await;
    insert_gateway_with_backup(&pool, "gw_route_degraded", "provider_primary", "provider_backup")
        .await;

    sqlx::query(
        r#"
        INSERT INTO provider_health_states (
            id, provider_id, scope, gateway_id, model, status, failure_streak, success_streak
        )
        VALUES (?1, ?2, 'gateway', ?3, '', 'degraded', 1, 0)
        "#,
    )
    .bind("provider_primary:gw_route_degraded")
    .bind("provider_primary")
    .bind("gw_route_degraded")
    .execute(&pool)
    .await
    .expect("mark primary degraded");

    let selector = RouteSelector::new(pool);
    let target = selector
        .select("gw_route_degraded")
        .await
        .expect("select route target");

    assert_eq!(target.provider_id, "provider_backup");
}

#[tokio::test]
async fn route_selector_applies_gateway_scoped_health_without_affecting_other_gateways() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    insert_provider(&pool, "provider_primary", "https://primary.example/v1").await;
    insert_provider(&pool, "provider_backup", "https://backup.example/v1").await;
    insert_gateway_with_backup(&pool, "gw_scope_a", "provider_primary", "provider_backup").await;
    insert_gateway_with_backup(&pool, "gw_scope_b", "provider_primary", "provider_backup").await;

    sqlx::query(
        r#"
        INSERT INTO provider_health_states (
            id, provider_id, scope, gateway_id, model, status, failure_streak, success_streak, circuit_open_until
        )
        VALUES (?1, ?2, 'gateway', ?3, '', 'unhealthy', 3, 0, '999999999999999999')
        "#,
    )
    .bind("provider_primary:gw_scope_a")
    .bind("provider_primary")
    .bind("gw_scope_a")
    .execute(&pool)
    .await
    .expect("mark gw_scope_a primary unhealthy");

    let selector = RouteSelector::new(pool.clone());
    let scoped_a = selector
        .select("gw_scope_a")
        .await
        .expect("select gw_scope_a route target");
    let scoped_b = selector
        .select("gw_scope_b")
        .await
        .expect("select gw_scope_b route target");

    assert_eq!(scoped_a.provider_id, "provider_backup");
    assert_eq!(scoped_b.provider_id, "provider_primary");
}

async fn insert_provider(pool: &sqlx::SqlitePool, provider_id: &str, base_url: &str) {
    sqlx::query(
        r#"
        INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
    )
    .bind(provider_id)
    .bind(format!("Provider {provider_id}"))
    .bind("openai")
    .bind(base_url)
    .bind(format!("sk-{provider_id}"))
    .bind(1_i64)
    .execute(pool)
    .await
    .expect("insert provider");
}

async fn insert_gateway_with_backup(
    pool: &sqlx::SqlitePool,
    gateway_id: &str,
    primary_provider_id: &str,
    backup_provider_id: &str,
) {
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
    .bind(gateway_id)
    .bind(format!("Gateway {gateway_id}"))
    .bind("127.0.0.1")
    .bind(18082_i64)
    .bind("openai")
    .bind("provider_default")
    .bind(json!({"compatibility_mode": "compatible"}).to_string())
    .bind(primary_provider_id)
    .bind("gpt-4o-mini")
    .bind(1_i64)
    .bind(0_i64)
    .execute(pool)
    .await
    .expect("insert gateway");

    sqlx::query(
        r#"
        UPDATE gateway_route_targets
        SET provider_id = ?2
        WHERE gateway_id = ?1 AND priority = 0
        "#,
    )
    .bind(gateway_id)
    .bind(primary_provider_id)
    .execute(pool)
    .await
    .expect("set primary route target");

    sqlx::query(
        r#"
        INSERT INTO gateway_route_targets (id, gateway_id, provider_id, priority, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5)
        "#,
    )
    .bind(format!("{gateway_id}__route__1"))
    .bind(gateway_id)
    .bind(backup_provider_id)
    .bind(1_i64)
    .bind(1_i64)
    .execute(pool)
    .await
    .expect("insert backup route target");
}

#[tokio::test]
async fn route_selector_only_applies_unhealthy_state_within_current_gateway_scope() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    for (id, url) in [
        ("provider_primary", "https://primary.example/v1"),
        ("provider_backup", "https://backup.example/v1"),
    ] {
        sqlx::query(
            r#"
            INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            "#,
        )
        .bind(id)
        .bind(format!("Provider {id}"))
        .bind("openai")
        .bind(url)
        .bind(format!("sk-{id}"))
        .bind(1_i64)
        .execute(&pool)
        .await
        .expect("insert provider");
    }

    for gateway_id in ["gw_scope_a", "gw_scope_b"] {
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
        .bind(gateway_id)
        .bind(format!("Gateway {gateway_id}"))
        .bind("127.0.0.1")
        .bind(if gateway_id == "gw_scope_a" { 18091_i64 } else { 18092_i64 })
        .bind("openai")
        .bind("provider_default")
        .bind(json!({}).to_string())
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
        .bind(gateway_id)
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
        .bind(format!("{gateway_id}__route__1"))
        .bind(gateway_id)
        .bind("provider_backup")
        .bind(1_i64)
        .bind(1_i64)
        .execute(&pool)
        .await
        .expect("insert backup route target");
    }

    sqlx::query(
        r#"
        INSERT INTO provider_health_states (
            provider_id, scope, gateway_id, model, status, failure_streak, success_streak, circuit_open_until, recover_after
        )
        VALUES (?1, 'gateway_provider', ?2, '', 'unhealthy', 3, 0, '9999999999', '9999999999')
        "#,
    )
    .bind("provider_primary")
    .bind("gw_scope_a")
    .execute(&pool)
    .await
    .expect("insert scoped unhealthy state");

    let selector = RouteSelector::new(pool);

    let target_a = selector
        .select("gw_scope_a")
        .await
        .expect("select target for gateway a");
    assert_eq!(target_a.provider_id, "provider_backup");

    let target_b = selector
        .select("gw_scope_b")
        .await
        .expect("select target for gateway b");
    assert_eq!(target_b.provider_id, "provider_primary");
}
