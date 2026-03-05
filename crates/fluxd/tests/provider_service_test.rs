use fluxd::domain::provider::{CreateProviderInput, Provider};
use fluxd::service::provider_service::ProviderService;
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
    assert_eq!(p.models, vec!["gpt-4o-mini".to_string(), "gpt-4.1".to_string()]);
    assert!(p.enabled);
}
