use fluxd::storage::migrate::run_migrations;
use sqlx::migrate::Migrator;
use sqlx::sqlite::SqlitePoolOptions;

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

#[tokio::test]
async fn migration_adds_request_log_forwarding_columns() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");

    run_migrations(&pool).await.expect("run migrations");

    for column in [
        "inbound_protocol",
        "upstream_protocol",
        "model_requested",
        "model_effective",
        "stream",
        "first_byte_ms",
        "input_tokens",
        "output_tokens",
        "cached_tokens",
        "total_tokens",
        "usage_json",
        "error_stage",
        "error_type",
        "failover_performed",
        "route_attempt_count",
        "provider_id_initial",
    ] {
        let found = sqlx::query_scalar::<_, String>(
            "SELECT name FROM pragma_table_info('request_logs') WHERE name = ?1",
        )
        .bind(column)
        .fetch_optional(&pool)
        .await
        .expect("query request_logs columns");

        assert_eq!(found.as_deref(), Some(column));
    }
}

#[tokio::test]
async fn migration_removes_request_log_resource_foreign_keys() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");

    run_migrations(&pool).await.expect("run migrations");

    let foreign_key_count = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM pragma_foreign_key_list('request_logs')",
    )
    .fetch_one(&pool)
    .await
    .expect("query request_logs foreign keys");

    assert_eq!(foreign_key_count, 0);
}

#[tokio::test]
async fn migration_backfills_gateway_route_targets_from_default_provider() {
    let pool = SqlitePoolOptions::new()
        .max_connections(1)
        .connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");

    seed_schema_through_migration_006(&pool).await;

    sqlx::query(
        r#"
        INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5, ?6)
        "#,
    )
    .bind("provider_route_target")
    .bind("Provider Route Target")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-route-target")
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
    .bind("gateway_route_target")
    .bind("Gateway Route Target")
    .bind("127.0.0.1")
    .bind(18080_i64)
    .bind("openai")
    .bind("provider_route_target")
    .bind(Option::<String>::None)
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert gateway");

    run_migrations(&pool).await.expect("run migrations");

    let route_target_table = sqlx::query_scalar::<_, String>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'gateway_route_targets'",
    )
    .fetch_optional(&pool)
    .await
    .expect("query gateway_route_targets table");
    assert_eq!(route_target_table.as_deref(), Some("gateway_route_targets"));

    let health_table = sqlx::query_scalar::<_, String>(
        "SELECT name FROM sqlite_master WHERE type = 'table' AND name = 'provider_health_states'",
    )
    .fetch_optional(&pool)
    .await
    .expect("query provider_health_states table");
    assert_eq!(health_table.as_deref(), Some("provider_health_states"));

    for column in ["gateway_id", "model"] {
        let found = sqlx::query_scalar::<_, String>(
            "SELECT name FROM pragma_table_info('provider_health_states') WHERE name = ?1",
        )
        .bind(column)
        .fetch_optional(&pool)
        .await
        .expect("query provider_health_states columns");

        assert_eq!(found.as_deref(), Some(column));
    }

    let route_target = sqlx::query_as::<_, (String, i64, i64)>(
        r#"
        SELECT provider_id, priority, enabled
        FROM gateway_route_targets
        WHERE gateway_id = ?1
        "#,
    )
    .bind("gateway_route_target")
    .fetch_one(&pool)
    .await
    .expect("fetch route target");

    assert_eq!(route_target.0, "provider_route_target");
    assert_eq!(route_target.1, 0);
    assert_eq!(route_target.2, 1);
}

async fn seed_schema_through_migration_006(pool: &sqlx::SqlitePool) {
    static MIGRATOR: Migrator = sqlx::migrate!("./migrations");

    sqlx::query(
        r#"
        CREATE TABLE IF NOT EXISTS _sqlx_migrations (
            version BIGINT PRIMARY KEY,
            description TEXT NOT NULL,
            installed_on TIMESTAMP NOT NULL DEFAULT CURRENT_TIMESTAMP,
            success BOOLEAN NOT NULL,
            checksum BLOB NOT NULL,
            execution_time BIGINT NOT NULL
        )
        "#,
    )
    .execute(pool)
    .await
    .expect("create _sqlx_migrations");

    for migration in MIGRATOR.migrations.iter().take(6) {
        for statement in migration
            .sql
            .split(';')
            .map(str::trim)
            .filter(|statement| !statement.is_empty() && !statement.starts_with("--"))
        {
            sqlx::query(statement)
                .execute(pool)
                .await
                .unwrap_or_else(|error| {
                    panic!("apply seeded migration {}: {error}", migration.version)
                });
        }

        sqlx::query(
            r#"
            INSERT INTO _sqlx_migrations (
                version, description, success, checksum, execution_time
            )
            VALUES (?1, ?2, 1, ?3, 0)
            "#,
        )
        .bind(migration.version)
        .bind(migration.description.as_ref())
        .bind(migration.checksum.as_ref())
        .execute(pool)
        .await
        .unwrap_or_else(|error| panic!("record seeded migration {}: {error}", migration.version));
    }
}
