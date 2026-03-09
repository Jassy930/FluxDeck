use fluxd::storage::migrate::run_migrations;

#[tokio::test]
async fn migration_creates_core_tables() {
    let db_url = "sqlite::memory:";
    let pool = sqlx::SqlitePool::connect(db_url)
        .await
        .expect("connect sqlite memory db");

    run_migrations(&pool).await.expect("run migrations");

    let (count,): (i64,) = sqlx::query_as(
        "SELECT COUNT(*) FROM sqlite_master WHERE type = 'table' AND name IN ('providers', 'provider_models', 'gateways', 'request_logs')",
    )
    .fetch_one(&pool)
    .await
    .expect("query sqlite_master");

    assert_eq!(count, 4);
}

#[tokio::test]
async fn migration_adds_gateway_protocol_config_columns_with_defaults() {
    let db_url = "sqlite::memory:";
    let pool = sqlx::SqlitePool::connect(db_url)
        .await
        .expect("connect sqlite memory db");

    run_migrations(&pool).await.expect("run migrations");

    let protocol_col = sqlx::query_scalar::<_, String>(
        "SELECT name FROM pragma_table_info('gateways') WHERE name = 'upstream_protocol'",
    )
    .fetch_optional(&pool)
    .await
    .expect("query gateways columns");
    assert_eq!(protocol_col.as_deref(), Some("upstream_protocol"));

    let config_col = sqlx::query_scalar::<_, String>(
        "SELECT name FROM pragma_table_info('gateways') WHERE name = 'protocol_config_json'",
    )
    .fetch_optional(&pool)
    .await
    .expect("query gateways columns");
    assert_eq!(config_col.as_deref(), Some("protocol_config_json"));

    let auto_start_col = sqlx::query_scalar::<_, String>(
        "SELECT name FROM pragma_table_info('gateways') WHERE name = 'auto_start'",
    )
    .fetch_optional(&pool)
    .await
    .expect("query gateways columns");
    assert_eq!(auto_start_col.as_deref(), Some("auto_start"));

    sqlx::query(
        r#"
        INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
    )
    .bind("provider_for_migration")
    .bind("Provider For Migration")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-migration")
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert provider");

    sqlx::query(
        r#"
        INSERT INTO gateways (
            id, name, listen_host, listen_port, inbound_protocol,
            default_provider_id, default_model, enabled
        )
        VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
        "#,
    )
    .bind("gateway_for_migration")
    .bind("Gateway For Migration")
    .bind("127.0.0.1")
    .bind(8080_i64)
    .bind("openai")
    .bind("provider_for_migration")
    .bind(Option::<String>::None)
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert gateway");

    let row = sqlx::query_as::<_, (String, String, i64)>(
        "SELECT upstream_protocol, protocol_config_json, auto_start FROM gateways WHERE id = ?1",
    )
    .bind("gateway_for_migration")
    .fetch_one(&pool)
    .await
    .expect("query gateway protocol defaults");

    assert_eq!(row.0, "provider_default");
    assert_eq!(row.1, "{}");
    assert_eq!(row.2, 0);
}
