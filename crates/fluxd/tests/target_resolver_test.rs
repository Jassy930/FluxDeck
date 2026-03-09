use fluxd::forwarding::target_resolver::TargetResolver;
use fluxd::storage::migrate::run_migrations;
use serde_json::json;

#[tokio::test]
async fn resolves_gateway_target_with_upstream_protocol() {
    let resolver = build_test_resolver().await;

    let target = resolver
        .resolve("gw_anthropic_native")
        .await
        .expect("resolve target");

    assert_eq!(target.upstream_protocol, "anthropic");
    assert_eq!(target.provider_id, "provider_anthropic");
    assert_eq!(target.effective_model.as_deref(), Some("claude-sonnet-4-5"));
}

async fn build_test_resolver() -> TargetResolver {
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
    .bind("provider_anthropic")
    .bind("Anthropic Provider")
    .bind("anthropic")
    .bind("https://api.anthropic.com/v1")
    .bind("sk-anthropic")
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        r#"
        INSERT INTO gateways (
            id, name, listen_host, listen_port, inbound_protocol,
            upstream_protocol, protocol_config_json, default_provider_id,
            default_model, enabled
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10)
        "#,
    )
    .bind("gw_anthropic_native")
    .bind("Anthropic Native Gateway")
    .bind("127.0.0.1")
    .bind(18081_i64)
    .bind("anthropic")
    .bind("anthropic")
    .bind(json!({"compatibility_mode": "compatible"}).to_string())
    .bind("provider_anthropic")
    .bind("claude-sonnet-4-5")
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert gateway");

    TargetResolver::new(pool)
}
