use anyhow::Result;
use sqlx::SqlitePool;

pub async fn run_migrations(pool: &SqlitePool) -> Result<()> {
    sqlx::migrate!("./migrations").run(pool).await?;
    repair_request_log_resource_foreign_keys(pool).await?;
    Ok(())
}

async fn repair_request_log_resource_foreign_keys(pool: &SqlitePool) -> Result<()> {
    let mut conn = pool.acquire().await?;

    let foreign_key_count = sqlx::query_scalar::<_, i64>(
        "SELECT COUNT(*) FROM pragma_foreign_key_list('request_logs')",
    )
    .fetch_one(&mut *conn)
    .await?;

    if foreign_key_count == 0 {
        return Ok(());
    }

    sqlx::query("PRAGMA foreign_keys=OFF")
        .execute(&mut *conn)
        .await?;

    sqlx::query(
        r#"
        CREATE TABLE request_logs_new (
            request_id TEXT PRIMARY KEY,
            gateway_id TEXT NOT NULL,
            provider_id TEXT NOT NULL,
            model TEXT,
            status_code INTEGER NOT NULL,
            latency_ms INTEGER NOT NULL,
            error TEXT,
            created_at TEXT NOT NULL DEFAULT CURRENT_TIMESTAMP,
            inbound_protocol TEXT,
            upstream_protocol TEXT,
            model_requested TEXT,
            model_effective TEXT,
            stream INTEGER NOT NULL DEFAULT 0,
            first_byte_ms INTEGER,
            input_tokens INTEGER,
            output_tokens INTEGER,
            cached_tokens INTEGER,
            total_tokens INTEGER,
            usage_json TEXT,
            error_stage TEXT,
            error_type TEXT
        )
        "#,
    )
    .execute(&mut *conn)
    .await?;

    sqlx::query(
        r#"
        INSERT INTO request_logs_new (
            request_id,
            gateway_id,
            provider_id,
            model,
            status_code,
            latency_ms,
            error,
            created_at,
            inbound_protocol,
            upstream_protocol,
            model_requested,
            model_effective,
            stream,
            first_byte_ms,
            input_tokens,
            output_tokens,
            cached_tokens,
            total_tokens,
            usage_json,
            error_stage,
            error_type
        )
        SELECT
            request_id,
            gateway_id,
            provider_id,
            model,
            status_code,
            latency_ms,
            error,
            created_at,
            inbound_protocol,
            upstream_protocol,
            model_requested,
            model_effective,
            stream,
            first_byte_ms,
            input_tokens,
            output_tokens,
            cached_tokens,
            total_tokens,
            usage_json,
            error_stage,
            error_type
        FROM request_logs
        "#,
    )
    .execute(&mut *conn)
    .await?;

    sqlx::query("DROP TABLE request_logs")
        .execute(&mut *conn)
        .await?;
    sqlx::query("ALTER TABLE request_logs_new RENAME TO request_logs")
        .execute(&mut *conn)
        .await?;
    sqlx::query("PRAGMA foreign_keys=ON")
        .execute(&mut *conn)
        .await?;

    Ok(())
}
