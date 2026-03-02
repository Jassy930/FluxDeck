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
