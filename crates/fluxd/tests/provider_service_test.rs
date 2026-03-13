use fluxd::domain::provider::{CreateProviderInput, Provider};
use fluxd::service::provider_service::{DeleteProviderResult, ProviderService};
use fluxd::storage::migrate::run_migrations;

#[tokio::test]
async fn create_and_get_provider() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let service = ProviderService::new(pool.clone());

    let created = service
        .create_provider(CreateProviderInput {
            id: "provider_1".to_string(),
            name: "OpenAI Main".to_string(),
            kind: "openai".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_key: "sk-test-1".to_string(),
            models: vec!["gpt-4o-mini".to_string(), "gpt-4.1".to_string()],
            enabled: true,
        })
        .await
        .expect("create provider");

    assert_eq!(created.id, "provider_1");

    let got = service
        .get_provider_by_id("provider_1")
        .await
        .expect("get provider")
        .expect("provider exists");

    assert_provider(&got);

    let listed = service.list_providers().await.expect("list providers");
    assert_eq!(listed.len(), 1);
    assert_provider(&listed[0]);

    let updated = service
        .update_provider(
            "provider_1",
            fluxd::domain::provider::UpdateProviderInput {
                name: "OpenAI Backup".to_string(),
                kind: "openai".to_string(),
                base_url: "https://api.openai.com/v1".to_string(),
                api_key: "sk-test-2".to_string(),
                models: vec!["gpt-4.1-mini".to_string()],
                enabled: false,
            },
        )
        .await
        .expect("update provider")
        .expect("provider should exist");

    assert_eq!(updated.id, "provider_1");
    assert_eq!(updated.name, "OpenAI Backup");
    assert_eq!(updated.api_key, "sk-test-2");
    assert_eq!(updated.models, vec!["gpt-4.1-mini".to_string()]);
    assert!(!updated.enabled);
}

fn assert_provider(p: &Provider) {
    assert_eq!(p.id, "provider_1");
    assert_eq!(p.name, "OpenAI Main");
    assert_eq!(p.kind, "openai");
    assert_eq!(p.base_url, "https://api.openai.com/v1");
    assert_eq!(p.api_key, "sk-test-1");
    assert_eq!(
        p.models,
        vec!["gpt-4o-mini".to_string(), "gpt-4.1".to_string()]
    );
    assert!(p.enabled);
}

#[tokio::test]
async fn create_provider_rejects_unknown_kind() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let service = ProviderService::new(pool);

    let err = service
        .create_provider(CreateProviderInput {
            id: "provider_invalid".to_string(),
            name: "Invalid Provider".to_string(),
            kind: "not-supported".to_string(),
            base_url: "https://example.com/v1".to_string(),
            api_key: "sk-invalid".to_string(),
            models: vec!["model-a".to_string()],
            enabled: true,
        })
        .await
        .expect_err("unsupported kind should fail");

    let message = err.to_string();
    assert!(message.contains("not-supported"));
    assert!(message.contains("openai"));
    assert!(message.contains("ollama"));
}

#[tokio::test]
async fn update_provider_rejects_unknown_kind() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let service = ProviderService::new(pool.clone());

    service
        .create_provider(CreateProviderInput {
            id: "provider_update_invalid".to_string(),
            name: "Valid Provider".to_string(),
            kind: "openai".to_string(),
            base_url: "https://api.openai.com/v1".to_string(),
            api_key: "sk-valid".to_string(),
            models: vec!["gpt-4o-mini".to_string()],
            enabled: true,
        })
        .await
        .expect("seed valid provider");

    let err = service
        .update_provider(
            "provider_update_invalid",
            fluxd::domain::provider::UpdateProviderInput {
                name: "Still Invalid".to_string(),
                kind: "bad-kind".to_string(),
                base_url: "https://example.com/v1".to_string(),
                api_key: "sk-invalid".to_string(),
                models: vec!["model-b".to_string()],
                enabled: false,
            },
        )
        .await
        .expect_err("unsupported update kind should fail");

    let message = err.to_string();
    assert!(message.contains("bad-kind"));
    assert!(message.contains("azure-openai"));
    assert!(message.contains("new-api"));
}

#[tokio::test]
async fn delete_provider_rejects_gateway_route_target_reference() {
    let pool = sqlx::SqlitePool::connect("sqlite::memory:")
        .await
        .expect("connect sqlite memory db");
    run_migrations(&pool).await.expect("run migrations");

    let service = ProviderService::new(pool.clone());

    for (id, name) in [
        ("provider_primary", "Primary Provider"),
        ("provider_backup", "Backup Provider"),
    ] {
        service
            .create_provider(CreateProviderInput {
                id: id.to_string(),
                name: name.to_string(),
                kind: "openai".to_string(),
                base_url: "https://api.openai.com/v1".to_string(),
                api_key: format!("sk-{id}"),
                models: vec!["gpt-4o-mini".to_string()],
                enabled: true,
            })
            .await
            .expect("create provider");
    }

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
    .bind("gateway_route_ref")
    .bind("Gateway Route Ref")
    .bind("127.0.0.1")
    .bind(18080_i64)
    .bind("openai")
    .bind("provider_default")
    .bind("{}")
    .bind("provider_primary")
    .bind(Option::<String>::None)
    .bind(1_i64)
    .bind(0_i64)
    .execute(&pool)
    .await
    .expect("insert gateway");

    sqlx::query(
        r#"
        INSERT INTO gateway_route_targets (id, gateway_id, provider_id, priority, enabled)
        VALUES (?1, ?2, ?3, ?4, ?5)
        "#,
    )
    .bind("gateway_route_ref__route__1")
    .bind("gateway_route_ref")
    .bind("provider_backup")
    .bind(1_i64)
    .bind(1_i64)
    .execute(&pool)
    .await
    .expect("insert gateway route target");

    let result = service
        .delete_provider("provider_backup")
        .await
        .expect("delete provider result");

    assert_eq!(
        result,
        DeleteProviderResult::ReferencedByGateways(vec!["gateway_route_ref".to_string()])
    );
}
