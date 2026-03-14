use fluxd::domain::provider::CreateProviderInput;
use fluxd::service::provider_health_service::ProviderHealthService;
use fluxd::service::provider_service::ProviderService;
use fluxd::storage::migrate::run_migrations;

#[tokio::test]
async fn provider_health_service_marks_provider_unhealthy_after_three_failures() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_health_fail".to_string(),
            name: "Provider Health Fail".to_string(),
            kind: "openai".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_key: "sk-health-fail".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let service = ProviderHealthService::new(pool.clone());

    for _ in 0..3 {
        service
            .record_failure("provider_health_fail", "timeout")
            .await
            .expect("record failure");
    }

    let state = service
        .get_state("provider_health_fail")
        .await
        .expect("get health state")
        .expect("health state exists");

    assert_eq!(state.status, "unhealthy");
    assert_eq!(state.failure_streak, 3);
    assert_eq!(state.last_failure_reason.as_deref(), Some("timeout"));
    assert!(state.circuit_open_until.is_some());
}

#[tokio::test]
async fn provider_health_service_moves_from_probing_to_healthy_after_probe_and_successes() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_health_recover".to_string(),
            name: "Provider Health Recover".to_string(),
            kind: "openai".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_key: "sk-health-recover".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let service = ProviderHealthService::new(pool.clone());

    for _ in 0..3 {
        service
            .record_failure("provider_health_recover", "timeout")
            .await
            .expect("record failure");
    }

    service
        .mark_probe_result("provider_health_recover", true, None)
        .await
        .expect("mark probe success");

    let probing = service
        .get_state("provider_health_recover")
        .await
        .expect("get probing state")
        .expect("probing state exists");
    assert_eq!(probing.status, "probing");

    service
        .record_success("provider_health_recover")
        .await
        .expect("record first success");
    service
        .record_success("provider_health_recover")
        .await
        .expect("record second success");

    let recovered = service
        .get_state("provider_health_recover")
        .await
        .expect("get recovered state")
        .expect("recovered state exists");
    assert_eq!(recovered.status, "healthy");
    assert_eq!(recovered.success_streak, 2);
    assert_eq!(recovered.failure_streak, 0);
}

#[tokio::test]
async fn provider_health_service_tracks_gateway_scoped_failures_without_touching_other_gateways() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_health_scope".to_string(),
            name: "Provider Health Scope".to_string(),
            kind: "openai".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_key: "sk-health-scope".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let service = ProviderHealthService::new(pool.clone());

    for _ in 0..3 {
        service
            .record_failure_for_gateway("gw_scope_a", "provider_health_scope", "timeout")
            .await
            .expect("record scoped failure");
    }

    let scoped = service
        .get_scoped_state("provider_health_scope", Some("gw_scope_a"), None)
        .await
        .expect("get scoped health state")
        .expect("scoped health state exists");
    assert_eq!(scoped.status, "unhealthy");
    assert_eq!(scoped.gateway_id.as_deref(), Some("gw_scope_a"));
    assert!(scoped.recover_after.is_some());

    let other_gateway = service
        .get_scoped_state("provider_health_scope", Some("gw_scope_b"), None)
        .await
        .expect("get other gateway state");
    assert!(other_gateway.is_none());

    let global = service
        .get_state("provider_health_scope")
        .await
        .expect("get global state")
        .expect("global state exists");
    assert_eq!(global.scope, "global");
}

#[tokio::test]
async fn provider_health_service_probe_provider_promotes_gateway_scoped_unhealthy_state() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let provider_service = ProviderService::new(pool.clone());
    provider_service
        .create_provider(CreateProviderInput {
            id: "provider_health_probe_scope".to_string(),
            name: "Provider Health Probe Scope".to_string(),
            kind: "openai".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_key: "sk-health-probe-scope".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    let service = ProviderHealthService::new(pool.clone());
    for _ in 0..3 {
        service
            .record_failure_for_gateway("gw_probe_scope", "provider_health_probe_scope", "timeout")
            .await
            .expect("record scoped failure");
    }

    service
        .probe_provider("provider_health_probe_scope")
        .await
        .expect("probe provider");

    let scoped = service
        .get_scoped_state("provider_health_probe_scope", Some("gw_probe_scope"), None)
        .await
        .expect("get scoped health state")
        .expect("scoped health state exists");
    assert_eq!(scoped.status, "probing");

    let global = service
        .get_state("provider_health_probe_scope")
        .await
        .expect("get global state")
        .expect("global state exists");
    assert_eq!(global.status, "probing");
}
