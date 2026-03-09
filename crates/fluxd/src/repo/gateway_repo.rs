use anyhow::Result;
use serde_json::{from_str, Value};
use sqlx::{Row, SqlitePool};

use crate::domain::gateway::{CreateGatewayInput, Gateway, UpdateGatewayInput};

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
                upstream_protocol, protocol_config_json,
                default_provider_id, default_model, enabled, auto_start
            )
            VALUES (?1, ?2, ?3, ?4, ?5, ?6, ?7, ?8, ?9, ?10, ?11)
            "#,
        )
        .bind(&input.id)
        .bind(&input.name)
        .bind(&input.listen_host)
        .bind(input.listen_port)
        .bind(&input.inbound_protocol)
        .bind(&input.upstream_protocol)
        .bind(input.protocol_config_json.to_string())
        .bind(&input.default_provider_id)
        .bind(&input.default_model)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .bind(if input.auto_start { 1_i64 } else { 0_i64 })
        .execute(&self.pool)
        .await?;

        Ok(Gateway {
            id: input.id,
            name: input.name,
            listen_host: input.listen_host,
            listen_port: input.listen_port,
            inbound_protocol: input.inbound_protocol,
            upstream_protocol: input.upstream_protocol,
            protocol_config_json: input.protocol_config_json,
            default_provider_id: input.default_provider_id,
            default_model: input.default_model,
            enabled: input.enabled,
            auto_start: input.auto_start,
        })
    }

    pub async fn get_by_id(&self, gateway_id: &str) -> Result<Option<Gateway>> {
        let row_opt = sqlx::query(
            r#"
            SELECT id, name, listen_host, listen_port, inbound_protocol,
                   upstream_protocol, protocol_config_json,
                   default_provider_id, default_model, enabled, auto_start
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

        let protocol_config_json: Value =
            from_str(&row.get::<String, _>("protocol_config_json"))?;

        Ok(Some(Gateway {
            id: row.get("id"),
            name: row.get("name"),
            listen_host: row.get("listen_host"),
            listen_port: row.get("listen_port"),
            inbound_protocol: row.get("inbound_protocol"),
            upstream_protocol: row.get("upstream_protocol"),
            protocol_config_json,
            default_provider_id: row.get("default_provider_id"),
            default_model: row.get("default_model"),
            enabled: row.get::<i64, _>("enabled") != 0,
            auto_start: row.get::<i64, _>("auto_start") != 0,
        }))
    }

    pub async fn update(
        &self,
        gateway_id: &str,
        input: UpdateGatewayInput,
    ) -> Result<Option<Gateway>> {
        let result = sqlx::query(
            r#"
            UPDATE gateways
            SET name = ?1,
                listen_host = ?2,
                listen_port = ?3,
                inbound_protocol = ?4,
                upstream_protocol = ?5,
                protocol_config_json = ?6,
                default_provider_id = ?7,
                default_model = ?8,
                enabled = ?9,
                auto_start = ?10,
                updated_at = CURRENT_TIMESTAMP
            WHERE id = ?11
            "#,
        )
        .bind(&input.name)
        .bind(&input.listen_host)
        .bind(input.listen_port)
        .bind(&input.inbound_protocol)
        .bind(&input.upstream_protocol)
        .bind(input.protocol_config_json.to_string())
        .bind(&input.default_provider_id)
        .bind(&input.default_model)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .bind(if input.auto_start { 1_i64 } else { 0_i64 })
        .bind(gateway_id)
        .execute(&self.pool)
        .await?;

        if result.rows_affected() == 0 {
            return Ok(None);
        }

        Ok(Some(Gateway {
            id: gateway_id.to_string(),
            name: input.name,
            listen_host: input.listen_host,
            listen_port: input.listen_port,
            inbound_protocol: input.inbound_protocol,
            upstream_protocol: input.upstream_protocol,
            protocol_config_json: input.protocol_config_json,
            default_provider_id: input.default_provider_id,
            default_model: input.default_model,
            enabled: input.enabled,
            auto_start: input.auto_start,
        }))
    }

    pub async fn list(&self) -> Result<Vec<Gateway>> {
        let rows = sqlx::query(
            r#"
            SELECT id, name, listen_host, listen_port, inbound_protocol,
                   upstream_protocol, protocol_config_json,
                   default_provider_id, default_model, enabled, auto_start
            FROM gateways
            ORDER BY created_at DESC
            "#,
        )
        .fetch_all(&self.pool)
        .await?;

        let gateways = rows
            .into_iter()
            .map(|row| -> Result<Gateway> {
                let protocol_config_json: Value =
                    from_str(&row.get::<String, _>("protocol_config_json"))?;
                Ok(Gateway {
                    id: row.get("id"),
                    name: row.get("name"),
                    listen_host: row.get("listen_host"),
                    listen_port: row.get("listen_port"),
                    inbound_protocol: row.get("inbound_protocol"),
                    upstream_protocol: row.get("upstream_protocol"),
                    protocol_config_json,
                    default_provider_id: row.get("default_provider_id"),
                    default_model: row.get("default_model"),
                    enabled: row.get::<i64, _>("enabled") != 0,
                    auto_start: row.get::<i64, _>("auto_start") != 0,
                })
            })
            .collect::<Result<Vec<_>>>()?;

        Ok(gateways)
    }
}
