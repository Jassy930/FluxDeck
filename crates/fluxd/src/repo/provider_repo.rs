use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::domain::provider::{CreateProviderInput, Provider};

#[derive(Clone)]
pub struct ProviderRepo {
    pool: SqlitePool,
}

impl ProviderRepo {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn create(&self, input: CreateProviderInput) -> Result<Provider> {
        let mut tx = self.pool.begin().await?;

        sqlx::query(
            r#"
            INSERT INTO providers (id, name, kind, base_url, api_key, enabled)
            VALUES (?1, ?2, ?3, ?4, ?5, ?6)
            "#,
        )
        .bind(&input.id)
        .bind(&input.name)
        .bind(&input.kind)
        .bind(&input.base_url)
        .bind(&input.api_key)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .execute(&mut *tx)
        .await?;

        for model in &input.models {
            let model_id = format!("{}_{}", &input.id, model.replace('/', "_"));
            sqlx::query(
                r#"
                INSERT INTO provider_models (id, provider_id, model_name)
                VALUES (?1, ?2, ?3)
                "#,
            )
            .bind(model_id)
            .bind(&input.id)
            .bind(model)
            .execute(&mut *tx)
            .await?;
        }

        tx.commit().await?;

        Ok(Provider {
            id: input.id,
            name: input.name,
            kind: input.kind,
            base_url: input.base_url,
            api_key: input.api_key,
            models: input.models,
            enabled: input.enabled,
        })
    }

    pub async fn get_by_id(&self, provider_id: &str) -> Result<Option<Provider>> {
        let row_opt = sqlx::query(
            r#"
            SELECT id, name, kind, base_url, api_key, enabled
            FROM providers
            WHERE id = ?1
            "#,
        )
        .bind(provider_id)
        .fetch_optional(&self.pool)
        .await?;

        let Some(row) = row_opt else {
            return Ok(None);
        };

        let models = self.list_models(provider_id).await?;

        Ok(Some(Provider {
            id: row.get("id"),
            name: row.get("name"),
            kind: row.get("kind"),
            base_url: row.get("base_url"),
            api_key: row.get("api_key"),
            models,
            enabled: row.get::<i64, _>("enabled") != 0,
        }))
    }

    pub async fn list(&self) -> Result<Vec<Provider>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, kind, base_url, api_key, enabled
            FROM providers
            ORDER BY created_at DESC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let mut providers = Vec::with_capacity(rows.len());
        for row in rows {
            let id: String = row.get("id");
            let models = self.list_models(&id).await?;

            providers.push(Provider {
                id,
                name: row.get("name"),
                kind: row.get("kind"),
                base_url: row.get("base_url"),
                api_key: row.get("api_key"),
                models,
                enabled: row.get::<i64, _>("enabled") != 0,
            });
        }

        Ok(providers)
    }

    async fn list_models(&self, provider_id: &str) -> Result<Vec<String>> {
        let rows = sqlx::query(
            r#"
            SELECT model_name
            FROM provider_models
            WHERE provider_id = ?1
            ORDER BY rowid ASC
            "#,
        )
        .bind(provider_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| row.get::<String, _>("model_name"))
            .collect())
    }
}
