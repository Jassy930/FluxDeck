use anyhow::Result;
use sqlx::{Row, SqlitePool};

use crate::domain::gateway::{CreateGatewayInput, Gateway};

#[derive(Clone)]
pub struct GatewayRepo {
    pool: SqlitePool,
}

impl GatewayRepo {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn create(&self, input: CreateGatewayInput) -> Result<Gateway> {
        sqlx::query(
            r#"
            INSERT INTO gateways (
                id, name, listen_host, listen_port, inbound_protocol,
                default_provider_id, default_model, enabled
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8)
            "#,
        )
        .bind(&input.id)
        .bind(&input.name)
        .bind(&input.listen_host)
        .bind(input.listen_port)
        .bind(&input.inbound_protocol)
        .bind(&input.default_provider_id)
        .bind(&input.default_model)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .execute(&self.pool)
        .await?;

        Ok(Gateway {
            id: input.id,
            name: input.name,
            listen_host: input.listen_host,
            listen_port: input.listen_port,
            inbound_protocol: input.inbound_protocol,
            default_provider_id: input.default_provider_id,
            default_model: input.default_model,
            enabled: input.enabled,
        })
    }

    pub async fn get_by_id(&self, gateway_id: &str) -> Result<Option<Gateway>> {
        let row_opt = sqlx::query(
            r#"
            SELECT id, name, listen_host, listen_port, inbound_protocol,
                   default_provider_id, default_model, enabled
            FROM gateways
            WHERE id = ?1
            "#,
        )
        .bind(gateway_id)
        .fetch_optional(&self.pool)
        .await?;

        let Some(row) = row_opt else {
            return Ok(None);
        };

        Ok(Some(Gateway {
            id: row.get("id"),
            name: row.get("name"),
            listen_host: row.get("listen_host"),
            listen_port: row.get("listen_port"),
            inbound_protocol: row.get("inbound_protocol"),
            default_provider_id: row.get("default_provider_id"),
            default_model: row.get("default_model"),
            enabled: row.get::<i64, _>("enabled") != 0,
        }))
    }

    pub async fn list(&self) -> Result<Vec<Gateway>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, listen_host, listen_port, inbound_protocol,
                   default_provider_id, default_model, enabled
            FROM gateways
            ORDER BY created_at DESC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let gateways = rows
            .into_iter()
            .map(|row| Gateway {
                id: row.get("id"),
                name: row.get("name"),
                listen_host: row.get("listen_host"),
                listen_port: row.get("listen_port"),
                inbound_protocol: row.get("inbound_protocol"),
                default_provider_id: row.get("default_provider_id"),
                default_model: row.get("default_model"),
                enabled: row.get::<i64, _>("enabled") != 0,
            })
            .collect();

        Ok(gateways)
    }
}
