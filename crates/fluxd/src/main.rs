use std::env;
use std::fs;
use std::path::PathBuf;
use std::str::FromStr;

use anyhow::{Context, Result};
use fluxd::http::admin_routes::{build_admin_router, AdminApiState};
use fluxd::storage::migrate::run_migrations;
use sqlx::sqlite::SqliteConnectOptions;
use sqlx::SqlitePool;
use tokio::net::TcpListener;

#[tokio::main]
async fn main() -> Result<()> {
    let db_path = resolve_db_path();
    ensure_parent_dir(&db_path)?;

    let db_url = format!("sqlite://{}", db_path.display());
    let options = SqliteConnectOptions::from_str(&db_url)
        .with_context(|| format!("parse sqlite options: {db_url}"))?
        .create_if_missing(true);
    let pool = SqlitePool::connect_with(options)
        .await
        .with_context(|| format!("connect sqlite db: {db_url}"))?;
    run_migrations(&pool).await.context("run migrations")?;

    let admin_addr = env::var("FLUXDECK_ADMIN_ADDR").unwrap_or_else(|_| "127.0.0.1:7777".to_string());
    let listener = TcpListener::bind(&admin_addr)
        .await
        .with_context(|| format!("bind admin listener: {admin_addr}"))?;

    let state = AdminApiState::new(pool);
    let gateway_manager = state.gateway_manager();
    match gateway_manager.start_auto_start_gateways().await {
        Ok(summary) => {
            println!(
                "fluxd gateway auto-start eligible={} started={} failed={}",
                summary.eligible, summary.started, summary.failed
            );
        }
        Err(err) => {
            eprintln!("fluxd gateway auto-start skipped: {err}");
        }
    }

    let app = build_admin_router(state);
    println!("fluxd admin listening on http://{admin_addr}");

    axum::serve(listener, app)
        .await
        .context("serve admin http")?;

    Ok(())
}

fn resolve_db_path() -> PathBuf {
    if let Ok(path) = env::var("FLUXDECK_DB_PATH") {
        return PathBuf::from(path);
    }

    let home = env::var("HOME").unwrap_or_else(|_| ".".to_string());
    PathBuf::from(home).join(".fluxdeck").join("fluxdeck.db")
}

fn ensure_parent_dir(path: &PathBuf) -> Result<()> {
    if let Some(parent) = path.parent() {
        fs::create_dir_all(parent)
            .with_context(|| format!("create db parent dir: {}", parent.display()))?;
    }
    Ok(())
}
