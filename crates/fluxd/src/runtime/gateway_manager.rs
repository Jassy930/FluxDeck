use std::collections::HashMap;

use anyhow::{anyhow, Result};
use sqlx::SqlitePool;
use tokio::net::TcpListener;
use tokio::sync::{oneshot, RwLock};
use tokio::task::JoinHandle;

use crate::domain::gateway::is_supported_gateway_inbound_protocol;
use crate::http::anthropic_routes::{build_anthropic_router, AnthropicRouteState};
use crate::http::openai_routes::{build_openai_router, OpenAiRouteState};
use crate::http::passthrough::{build_passthrough_router, PassthroughRouteState};
use crate::repo::gateway_repo::GatewayRepo;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GatewayRuntimeStatus {
    Running,
    Stopped,
}

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct GatewayAutoStartSummary {
    pub eligible: usize,
    pub started: usize,
    pub failed: usize,
}

impl GatewayRuntimeStatus {
    pub fn as_str(self) -> &'static str {
        match self {
            GatewayRuntimeStatus::Running => "running",
            GatewayRuntimeStatus::Stopped => "stopped",
        }
    }
}

struct RunningGateway {
    shutdown_tx: oneshot::Sender<()>,
    task: JoinHandle<()>,
}

pub struct GatewayManager {
    repo: GatewayRepo,
    pool: SqlitePool,
    running: RwLock<HashMap<String, RunningGateway>>,
    last_errors: RwLock<HashMap<String, String>>,
}

impl GatewayManager {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: GatewayRepo::new(pool.clone()),
            pool,
            running: RwLock::new(HashMap::new()),
            last_errors: RwLock::new(HashMap::new()),
        }
    }

    pub async fn start_gateway(&self, gateway_id: &str) -> Result<()> {
        {
            let running = self.running.read().await;
            if running.contains_key(gateway_id) {
                return Ok(());
            }
        }

        let result = self.start_gateway_inner(gateway_id).await;
        match result {
            Ok(_) => {
                self.clear_error(gateway_id).await;
                Ok(())
            }
            Err(err) => {
                self.set_error(gateway_id, err.to_string()).await;
                Err(err)
            }
        }
    }

    pub async fn start_auto_start_gateways(&self) -> Result<GatewayAutoStartSummary> {
        let gateways = self.repo.list().await?;
        let mut summary = GatewayAutoStartSummary::default();

        for gateway in gateways
            .into_iter()
            .filter(|gateway| gateway.enabled && gateway.auto_start)
        {
            summary.eligible += 1;
            match self.start_gateway(&gateway.id).await {
                Ok(_) => summary.started += 1,
                Err(_) => summary.failed += 1,
            }
        }

        Ok(summary)
    }

    async fn start_gateway_inner(&self, gateway_id: &str) -> Result<()> {
        let gateway = self
            .repo
            .get_by_id(gateway_id)
            .await?
            .ok_or_else(|| anyhow!("gateway not found: {gateway_id}"))?;

        let bind_addr = format!("{}:{}", gateway.listen_host, gateway.listen_port);
        let listener = TcpListener::bind(bind_addr).await?;

        let gateway_id = gateway.id.clone();
        let app = match gateway.inbound_protocol.as_str() {
            "openai" => build_openai_router(OpenAiRouteState::new(
                self.pool.clone(),
                gateway_id.clone(),
            )),
            "anthropic" => build_anthropic_router(AnthropicRouteState::new(
                self.pool.clone(),
                gateway_id.clone(),
            )),
            protocol if is_supported_gateway_inbound_protocol(protocol) => {
                build_passthrough_router(PassthroughRouteState::new(
                    self.pool.clone(),
                    gateway_id.clone(),
                    gateway.inbound_protocol.clone(),
                ))
            }
            unsupported => {
                return Err(anyhow!(
                    "unsupported inbound protocol `{unsupported}` for gateway `{gateway_id}`"
                ))
            }
        };

        let (shutdown_tx, shutdown_rx) = oneshot::channel();
        let task = tokio::spawn(async move {
            let _ = axum::serve(listener, app)
                .with_graceful_shutdown(async move {
                    let _ = shutdown_rx.await;
                })
                .await;
        });

        let mut running = self.running.write().await;
        running.insert(
            gateway_id.to_string(),
            RunningGateway { shutdown_tx, task },
        );

        Ok(())
    }

    pub async fn stop_gateway(&self, gateway_id: &str) -> Result<()> {
        let maybe_running = {
            let mut running = self.running.write().await;
            running.remove(gateway_id)
        };

        if let Some(running_gateway) = maybe_running {
            let _ = running_gateway.shutdown_tx.send(());
            let _ = running_gateway.task.await;
        }

        self.clear_error(gateway_id).await;
        Ok(())
    }

    pub async fn status(&self, gateway_id: &str) -> GatewayRuntimeStatus {
        let running = self.running.read().await;
        if running.contains_key(gateway_id) {
            GatewayRuntimeStatus::Running
        } else {
            GatewayRuntimeStatus::Stopped
        }
    }

    pub async fn last_error(&self, gateway_id: &str) -> Option<String> {
        let errors = self.last_errors.read().await;
        errors.get(gateway_id).cloned()
    }

    async fn set_error(&self, gateway_id: &str, error: String) {
        let mut errors = self.last_errors.write().await;
        errors.insert(gateway_id.to_string(), error);
    }

    async fn clear_error(&self, gateway_id: &str) {
        let mut errors = self.last_errors.write().await;
        errors.remove(gateway_id);
    }
}
