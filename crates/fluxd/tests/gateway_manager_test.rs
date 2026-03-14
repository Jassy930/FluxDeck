use std::net::TcpListener as StdTcpListener;
use std::sync::{
    atomic::{AtomicUsize, Ordering},
    Arc,
};
use std::time::Duration;

use fluxd::domain::gateway::CreateGatewayInput;
use fluxd::domain::provider::CreateProviderInput;
use fluxd::repo::gateway_repo::GatewayRepo;
use fluxd::runtime::gateway_manager::{
    GatewayAutoStartSummary, GatewayManager, GatewayRuntimeStatus,
};
use fluxd::runtime::health_monitor::HealthMonitor;
use fluxd::service::provider_health_service::ProviderHealthService;
use fluxd::service::provider_service::ProviderService;
use fluxd::storage::migrate::run_migrations;
use axum::{http::StatusCode, routing::get, Router};
use serde_json::json;
use tokio::net::TcpListener;

#[tokio::test]
async fn starts_multiple_gateways_on_different_ports() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_default")
    .bind("Default")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert default provider");

    let repo = GatewayRepo::new(pool.clone());
    let gw1 = repo
        .create(CreateGatewayInput {
            id: "gw_1".to_string(),
            name: "Gateway 1".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create gateway 1");

    let gw2 = repo
        .create(CreateGatewayInput {
            id: "gw_2".to_string(),
            name: "Gateway 2".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4.1".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create gateway 2");

    let manager = GatewayManager::new(pool);

    manager.start_gateway(&gw1.id).await.expect("start gw1");
    manager.start_gateway(&gw2.id).await.expect("start gw2");

    assert_eq!(manager.status(&gw1.id).await, GatewayRuntimeStatus::Running);
    assert_eq!(manager.status(&gw2.id).await, GatewayRuntimeStatus::Running);

    manager.stop_gateway(&gw1.id).await.expect("stop gw1");
    manager.stop_gateway(&gw2.id).await.expect("stop gw2");

    assert_eq!(manager.status(&gw1.id).await, GatewayRuntimeStatus::Stopped);
    assert_eq!(manager.status(&gw2.id).await, GatewayRuntimeStatus::Stopped);
}

#[tokio::test]
async fn routes_gateway_runtime_by_inbound_protocol() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_default")
    .bind("Default")
    .bind("openai")
    .bind("http://127.0.0.1:9/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert default provider");

    let repo = GatewayRepo::new(pool.clone());
    let openai_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_openai".to_string(),
            name: "Gateway OpenAI".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create openai gateway");

    let anthropic_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_anthropic".to_string(),
            name: "Gateway Anthropic".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "anthropic".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("claude-3-7-sonnet".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create anthropic gateway");

    let manager = GatewayManager::new(pool);
    manager
        .start_gateway(&openai_gateway.id)
        .await
        .expect("start openai gateway");
    manager
        .start_gateway(&anthropic_gateway.id)
        .await
        .expect("start anthropic gateway");

    let client = reqwest::Client::new();

    let openai_resp = client
        .post(format!(
            "http://127.0.0.1:{}/v1/messages",
            openai_gateway.listen_port
        ))
        .json(&json!({}))
        .send()
        .await
        .expect("call openai gateway");
    assert_eq!(openai_resp.status(), reqwest::StatusCode::BAD_GATEWAY);

    let anthropic_resp = client
        .post(format!(
            "http://127.0.0.1:{}/v1/messages",
            anthropic_gateway.listen_port
        ))
        .json(&json!({}))
        .send()
        .await
        .expect("call anthropic gateway");
    assert_ne!(anthropic_resp.status(), reqwest::StatusCode::NOT_FOUND);

    manager
        .stop_gateway(&openai_gateway.id)
        .await
        .expect("stop openai gateway");
    manager
        .stop_gateway(&anthropic_gateway.id)
        .await
        .expect("stop anthropic gateway");
}

#[tokio::test]
async fn starts_openai_response_gateway_runtime() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_response")
    .bind("OpenAI Response")
    .bind("openai-response")
    .bind("http://127.0.0.1:9/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert response provider");

    let repo = GatewayRepo::new(pool.clone());
    let response_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_openai_response".to_string(),
            name: "Gateway OpenAI Response".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai-response".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_response".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-5-codex".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create openai-response gateway");

    let manager = GatewayManager::new(pool);
    manager
        .start_gateway(&response_gateway.id)
        .await
        .expect("start openai-response gateway");

    assert_eq!(
        manager.status(&response_gateway.id).await,
        GatewayRuntimeStatus::Running
    );

    manager
        .stop_gateway(&response_gateway.id)
        .await
        .expect("stop openai-response gateway");
}

#[tokio::test]
async fn auto_start_only_starts_enabled_gateways_and_records_failures() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    sqlx::query(
        "INSERT INTO providers (id, name, kind, base_url, api_key, enabled) VALUES (?1, ?2, ?3, ?4, ?5, 1)",
    )
    .bind("provider_default")
    .bind("Default")
    .bind("openai")
    .bind("https://api.openai.com/v1")
    .bind("sk-test")
    .execute(&pool)
    .await
    .expect("insert default provider");

    let repo = GatewayRepo::new(pool.clone());
    let running_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_auto_running".to_string(),
            name: "Gateway Auto Running".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: true,
        })
        .await
        .expect("create running gateway");

    let manual_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_manual".to_string(),
            name: "Gateway Manual".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: false,
        })
        .await
        .expect("create manual gateway");

    let disabled_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_disabled".to_string(),
            name: "Gateway Disabled".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: next_free_port(),
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: false,
            auto_start: true,
        })
        .await
        .expect("create disabled gateway");

    let occupied_listener = StdTcpListener::bind("127.0.0.1:0").expect("bind occupied port");
    let occupied_port = occupied_listener
        .local_addr()
        .expect("read occupied local addr")
        .port() as i64;

    let conflict_gateway = repo
        .create(CreateGatewayInput {
            id: "gw_conflict".to_string(),
            name: "Gateway Conflict".to_string(),
            listen_host: "127.0.0.1".to_string(),
            listen_port: occupied_port,
            inbound_protocol: "openai".to_string(),
            upstream_protocol: "provider_default".to_string(),
            protocol_config_json: serde_json::json!({}),
            default_provider_id: "provider_default".to_string(),
            route_targets: vec![],
            default_model: Some("gpt-4o-mini".to_string()),
            enabled: true,
            auto_start: true,
        })
        .await
        .expect("create conflict gateway");

    let manager = GatewayManager::new(pool);
    let summary = manager
        .start_auto_start_gateways()
        .await
        .expect("start auto-start gateways");

    assert_eq!(
        summary,
        GatewayAutoStartSummary {
            eligible: 2,
            started: 1,
            failed: 1,
        }
    );
    assert_eq!(
        manager.status(&running_gateway.id).await,
        GatewayRuntimeStatus::Running
    );
    assert_eq!(
        manager.status(&manual_gateway.id).await,
        GatewayRuntimeStatus::Stopped
    );
    assert_eq!(
        manager.status(&disabled_gateway.id).await,
        GatewayRuntimeStatus::Stopped
    );
    assert_eq!(
        manager.status(&conflict_gateway.id).await,
        GatewayRuntimeStatus::Stopped
    );
    assert_eq!(manager.last_error(&running_gateway.id).await, None);
    assert!(manager.last_error(&conflict_gateway.id).await.is_some());

    drop(occupied_listener);

    manager
        .stop_gateway(&running_gateway.id)
        .await
        .expect("stop running gateway");
}

fn next_free_port() -> i64 {
    let listener = StdTcpListener::bind("127.0.0.1:0").expect("bind random port");
    let port = listener.local_addr().expect("read local addr").port() as i64;
    drop(listener);
    port
}

#[tokio::test]
async fn health_monitor_probes_unhealthy_providers_on_run_once() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let upstream = spawn_probe_target(StatusCode::UNAUTHORIZED).await;
    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_monitor_probe".to_string(),
            name: "Provider Monitor Probe".to_string(),
            kind: "openai".to_string(),
            base_url: format!("http://{}", upstream),
            api_key: "sk-monitor-probe".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let health_service = ProviderHealthService::new(pool.clone());
    for _ in 0..3 {
        health_service
            .record_failure("provider_monitor_probe", "timeout")
            .await
            .expect("record failure");
    }

    sqlx::query(
        "UPDATE provider_health_states SET recover_after = '0', circuit_open_until = '0' WHERE provider_id = ?1 AND scope = 'global' AND gateway_id = '' AND model = ''",
    )
    .bind("provider_monitor_probe")
    .execute(&pool)
    .await
    .expect("force recover_after due");

    let monitor = HealthMonitor::new(pool.clone(), Duration::from_millis(50));
    let summary = monitor.run_once().await.expect("run health monitor once");
    assert_eq!(summary.probed, 1);

    let state = health_service
        .get_state("provider_monitor_probe")
        .await
        .expect("get provider health")
        .expect("provider health exists");
    assert_eq!(state.status, "probing");
}

#[tokio::test]
async fn health_monitor_respects_recover_after_before_running_real_probe() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let probe_hits = Arc::new(AtomicUsize::new(0));
    let upstream_addr = spawn_probe_server(StatusCode::UNAUTHORIZED, probe_hits.clone()).await;

    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_monitor_delayed".to_string(),
            name: "Provider Monitor Delayed".to_string(),
            kind: "openai".to_string(),
            base_url: format!("http://{}/v1", upstream_addr),
            api_key: "sk-monitor-delayed".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let health_service = ProviderHealthService::new(pool.clone());
    for _ in 0..3 {
        health_service
            .record_failure("provider_monitor_delayed", "timeout")
            .await
            .expect("record failure");
    }

    sqlx::query(
        "UPDATE provider_health_states SET recover_after = '9999999999999999999', circuit_open_until = '9999999999999999999' WHERE provider_id = ?1",
    )
    .bind("provider_monitor_delayed")
    .execute(&pool)
    .await
    .expect("delay recover_after");

    let monitor = HealthMonitor::new(pool.clone(), Duration::from_millis(50));
    let first_summary = monitor.run_once().await.expect("run health monitor once");
    assert_eq!(first_summary.probed, 0);
    assert_eq!(probe_hits.load(Ordering::SeqCst), 0);

    sqlx::query(
        "UPDATE provider_health_states SET recover_after = '0', circuit_open_until = '0' WHERE provider_id = ?1",
    )
    .bind("provider_monitor_delayed")
    .execute(&pool)
    .await
    .expect("expire recover_after");

    let second_summary = monitor.run_once().await.expect("run health monitor second tick");
    assert_eq!(second_summary.probed, 1);
    assert_eq!(probe_hits.load(Ordering::SeqCst), 1);

    let state = health_service
        .get_state("provider_monitor_delayed")
        .await
        .expect("get delayed provider health")
        .expect("delayed provider health exists");
    assert_eq!(state.status, "probing");
}

#[tokio::test]
async fn health_monitor_backoffs_failed_real_probe() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let probe_hits = Arc::new(AtomicUsize::new(0));
    let upstream_addr = spawn_probe_server(StatusCode::BAD_GATEWAY, probe_hits.clone()).await;

    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_monitor_backoff".to_string(),
            name: "Provider Monitor Backoff".to_string(),
            kind: "openai".to_string(),
            base_url: format!("http://{}/v1", upstream_addr),
            api_key: "sk-monitor-backoff".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let health_service = ProviderHealthService::new(pool.clone());
    for _ in 0..3 {
        health_service
            .record_failure("provider_monitor_backoff", "timeout")
            .await
            .expect("record failure");
    }

    sqlx::query(
        "UPDATE provider_health_states SET recover_after = '0', circuit_open_until = '0' WHERE provider_id = ?1",
    )
    .bind("provider_monitor_backoff")
    .execute(&pool)
    .await
    .expect("expire recover_after");

    let monitor = HealthMonitor::new(pool.clone(), Duration::from_millis(50));
    let summary = monitor.run_once().await.expect("run health monitor once");
    assert_eq!(summary.probed, 1);
    assert_eq!(probe_hits.load(Ordering::SeqCst), 1);

    let state = health_service
        .get_state("provider_monitor_backoff")
        .await
        .expect("get backoff provider health")
        .expect("backoff provider health exists");
    assert_eq!(state.status, "unhealthy");
    assert_eq!(state.last_failure_reason.as_deref(), Some("probe status 502"));
    assert_ne!(state.recover_after.as_deref(), Some("0"));
}

async fn spawn_probe_server(
    status: StatusCode,
    hits: Arc<AtomicUsize>,
) -> std::net::SocketAddr {
    let app = Router::new().route(
        "/v1",
        get({
            let hits = hits.clone();
            move || {
                let hits = hits.clone();
                async move {
                    hits.fetch_add(1, Ordering::SeqCst);
                    status
                }
            }
        }),
    );

    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind random port");
    let addr = listener.local_addr().expect("read local addr");
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve probe app");
    });
    addr
}

#[tokio::test]
async fn health_monitor_respects_recover_after_before_probing() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let upstream = spawn_probe_target(StatusCode::UNAUTHORIZED).await;
    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_monitor_cooldown".to_string(),
            name: "Provider Monitor Cooldown".to_string(),
            kind: "openai".to_string(),
            base_url: format!("http://{}", upstream),
            api_key: "sk-monitor-cooldown".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let health_service = ProviderHealthService::new(pool.clone());
    for _ in 0..3 {
        health_service
            .record_failure("provider_monitor_cooldown", "timeout")
            .await
            .expect("record failure");
    }

    let monitor = HealthMonitor::new(pool.clone(), Duration::from_millis(50));
    let summary = monitor.run_once().await.expect("run health monitor once");
    assert_eq!(summary.probed, 0);

    let state = health_service
        .get_state("provider_monitor_cooldown")
        .await
        .expect("get provider health")
        .expect("provider health exists");
    assert_eq!(state.status, "unhealthy");
}

async fn spawn_probe_target(status: StatusCode) -> std::net::SocketAddr {
    async fn probe_ok() -> StatusCode {
        StatusCode::UNAUTHORIZED
    }

    async fn probe_bad() -> StatusCode {
        StatusCode::SERVICE_UNAVAILABLE
    }

    let app = if status == StatusCode::UNAUTHORIZED {
        Router::new().route("/", get(probe_ok))
    } else {
        Router::new().route("/", get(probe_bad))
    };

    let listener = TcpListener::bind("127.0.0.1:0")
        .await
        .expect("bind probe target");
    let addr = listener.local_addr().expect("probe target addr");
    tokio::spawn(async move {
        axum::serve(listener, app).await.expect("serve probe target");
    });
    addr
}
