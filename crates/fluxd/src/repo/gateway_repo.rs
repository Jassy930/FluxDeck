use anyhow::Result;
use serde_json::{from_str, Value};
use sqlx::{Row, SqlitePool};

use crate::domain::gateway::{
    validate_gateway_inbound_protocol, validate_gateway_upstream_protocol, CreateGatewayInput,
    Gateway, GatewayRouteTarget, GatewayRouteTargetInput, UpdateGatewayInput,
};

#[derive(Clone)]
pub struct GatewayRepo {
    pool: SqlitePool,
}

impl GatewayRepo {
    pub fn new(pool: SqlitePool) -> Self {
        Self { pool }
    }

    pub async fn create(&self, input: CreateGatewayInput) -> Result<Gateway> {
        validate_gateway_inbound_protocol(&input.inbound_protocol)?;
        validate_gateway_upstream_protocol(&input.upstream_protocol)?;
        let mut tx = self.pool.begin().await?;
        let route_targets =
            normalized_route_targets(&input.id, &input.default_provider_id, &input.route_targets);
        let default_provider_id = primary_provider_id(&input.default_provider_id, &route_targets);

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
        .bind(&default_provider_id)
        .bind(&input.default_model)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .bind(if input.auto_start { 1_i64 } else { 0_i64 })
        .execute(&mut *tx)
        .await?;

        self.replace_route_targets(&mut tx, &input.id, &route_targets)
            .await?;
        tx.commit().await?;

        Ok(Gateway {
            id: input.id,
            name: input.name,
            listen_host: input.listen_host,
            listen_port: input.listen_port,
            inbound_protocol: input.inbound_protocol,
            upstream_protocol: input.upstream_protocol,
            protocol_config_json: input.protocol_config_json,
            default_provider_id,
            route_targets,
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

        let protocol_config_json: Value = from_str(&row.get::<String, _>("protocol_config_json"))?;

        let route_targets = self.list_route_targets(gateway_id).await?;

        Ok(Some(Gateway {
            id: row.get("id"),
            name: row.get("name"),
            listen_host: row.get("listen_host"),
            listen_port: row.get("listen_port"),
            inbound_protocol: row.get("inbound_protocol"),
            upstream_protocol: row.get("upstream_protocol"),
            protocol_config_json,
            default_provider_id: row.get("default_provider_id"),
            route_targets,
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
        validate_gateway_inbound_protocol(&input.inbound_protocol)?;
        validate_gateway_upstream_protocol(&input.upstream_protocol)?;
        let mut tx = self.pool.begin().await?;
        let route_targets =
            normalized_route_targets(gateway_id, &input.default_provider_id, &input.route_targets);
        let default_provider_id = primary_provider_id(&input.default_provider_id, &route_targets);

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
        .bind(&default_provider_id)
        .bind(&input.default_model)
        .bind(if input.enabled { 1_i64 } else { 0_i64 })
        .bind(if input.auto_start { 1_i64 } else { 0_i64 })
        .bind(gateway_id)
        .execute(&mut *tx)
        .await?;

        if result.rows_affected() == 0 {
            return Ok(None);
        }

        self.replace_route_targets(&mut tx, gateway_id, &route_targets)
            .await?;
        tx.commit().await?;

        Ok(Some(Gateway {
            id: gateway_id.to_string(),
            name: input.name,
            listen_host: input.listen_host,
            listen_port: input.listen_port,
            inbound_protocol: input.inbound_protocol,
            upstream_protocol: input.upstream_protocol,
            protocol_config_json: input.protocol_config_json,
            default_provider_id,
            route_targets,
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

        let mut gateways = Vec::with_capacity(rows.len());
        for row in rows {
            let gateway_id = row.get::<String, _>("id");
            let route_targets = self.list_route_targets(&gateway_id).await?;
            let protocol_config_json: Value =
                from_str(&row.get::<String, _>("protocol_config_json"))?;
            gateways.push(Gateway {
                id: gateway_id,
                name: row.get("name"),
                listen_host: row.get("listen_host"),
                listen_port: row.get("listen_port"),
                inbound_protocol: row.get("inbound_protocol"),
                upstream_protocol: row.get("upstream_protocol"),
                protocol_config_json,
                default_provider_id: row.get("default_provider_id"),
                route_targets,
                default_model: row.get("default_model"),
                enabled: row.get::<i64, _>("enabled") != 0,
                auto_start: row.get::<i64, _>("auto_start") != 0,
            });
        }

        Ok(gateways)
    }

    pub async fn delete(&self, gateway_id: &str) -> Result<bool> {
        let mut tx = self.pool.begin().await?;

        sqlx::query("DELETE FROM gateway_route_targets WHERE gateway_id = ?1")
            .bind(gateway_id)
            .execute(&mut *tx)
            .await?;

        let result = sqlx::query("DELETE FROM gateways WHERE id = ?1")
            .bind(gateway_id)
            .execute(&mut *tx)
            .await?;

        tx.commit().await?;

        Ok(result.rows_affected() > 0)
    }

    async fn list_route_targets(&self, gateway_id: &str) -> Result<Vec<GatewayRouteTarget>> {
        let rows = sqlx::query(
            r#"
            SELECT id, gateway_id, provider_id, priority, enabled
            FROM gateway_route_targets
            WHERE gateway_id = ?1
            ORDER BY priority ASC, created_at ASC
            "#,
        )
        .bind(gateway_id)
        .fetch_all(&self.pool)
        .await?;

        Ok(rows
            .into_iter()
            .map(|row| GatewayRouteTarget {
                id: row.get("id"),
                gateway_id: row.get("gateway_id"),
                provider_id: row.get("provider_id"),
                priority: row.get("priority"),
                enabled: row.get::<i64, _>("enabled") != 0,
            })
            .collect())
    }

    async fn replace_route_targets(
        &self,
        tx: &mut sqlx::Transaction<'_, sqlx::Sqlite>,
        gateway_id: &str,
        route_targets: &[GatewayRouteTarget],
    ) -> Result<()> {
        sqlx::query("DELETE FROM gateway_route_targets WHERE gateway_id = ?1")
            .bind(gateway_id)
            .execute(&mut **tx)
            .await?;

        for route_target in route_targets {
            sqlx::query(
                r#"
                INSERT INTO gateway_route_targets (id, gateway_id, provider_id, priority, enabled)
                VALUES (?1, ?2, ?3, ?4, ?5)
                "#,
            )
            .bind(&route_target.id)
            .bind(&route_target.gateway_id)
            .bind(&route_target.provider_id)
            .bind(route_target.priority)
            .bind(if route_target.enabled { 1_i64 } else { 0_i64 })
            .execute(&mut **tx)
            .await?;
        }

        Ok(())
    }
}

pub(crate) fn normalized_route_targets(
    gateway_id: &str,
    default_provider_id: &str,
    route_targets: &[GatewayRouteTargetInput],
) -> Vec<GatewayRouteTarget> {
    if route_targets.is_empty() {
        return vec![GatewayRouteTarget {
            id: format!("{gateway_id}__route__0"),
            gateway_id: gateway_id.to_string(),
            provider_id: default_provider_id.to_string(),
            priority: 0,
            enabled: true,
        }];
    }

    let mut sorted_targets = route_targets.to_vec();
    sorted_targets.sort_by_key(|route_target| route_target.priority);

    sorted_targets
        .into_iter()
        .map(|route_target| GatewayRouteTarget {
            id: format!("{gateway_id}__route__{}", route_target.priority),
            gateway_id: gateway_id.to_string(),
            provider_id: route_target.provider_id,
            priority: route_target.priority,
            enabled: route_target.enabled,
        })
        .collect()
}

fn primary_provider_id(default_provider_id: &str, route_targets: &[GatewayRouteTarget]) -> String {
    route_targets
        .iter()
        .find(|route_target| route_target.enabled)
        .or_else(|| route_targets.first())
        .map(|route_target| route_target.provider_id.clone())
        .unwrap_or_else(|| default_provider_id.to_string())
}
