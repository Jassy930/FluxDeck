use std::collections::HashMap;

use anyhow::{anyhow, Result};
use sqlx::SqlitePool;
use tokio::net::TcpListener;
use tokio::sync::{oneshot, RwLock};
use tokio::task::JoinHandle;

use crate::repo::gateway_repo::GatewayRepo;

#[derive(Debug, Clone, Copy, PartialEq, Eq)]
pub enum GatewayRuntimeStatus {
    Running,
    Stopped,
}

struct RunningGateway {
    shutdown_tx: oneshot::Sender<()>,
    task: JoinHandle<()>,
}

pub struct GatewayManager {
    repo: GatewayRepo,
    running: RwLock<HashMap<String, RunningGateway>>,
}

impl GatewayManager {
    pub fn new(pool: SqlitePool) -> Self {
        Self {
            repo: GatewayRepo::new(pool),
            running: RwLock::new(HashMap::new()),
        }
    }

    pub async fn start_gateway(&self, gateway_id: &str) -> Result<()> {
        {
            let running = self.running.read().await;
            if running.contains_key(gateway_id) {
                return Ok(());
            }
        }

        let gateway = self
            .repo
            .get_by_id(gateway_id)
            .await?
            .ok_or_else(|| anyhow!("gateway not found: {gateway_id}"))?;

        let bind_addr = format!("{}:{}", gateway.listen_host, gateway.listen_port);
        let listener = TcpListener::bind(bind_addr).await?;

        let (shutdown_tx, mut shutdown_rx) = oneshot::channel();
        let task = tokio::spawn(async move {
            loop {
                tokio::select! {
                    _ = &mut shutdown_rx => {
                        break;
                    }
                    accept_result = listener.accept() => {
                        if accept_result.is_err() {
                            break;
                        }
                    }
                }
            }
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
}
