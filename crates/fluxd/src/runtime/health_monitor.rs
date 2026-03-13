use std::time::Duration;

use anyhow::Result;
use sqlx::SqlitePool;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::repo::provider_repo::ProviderRepo;
use crate::service::provider_health_service::ProviderHealthService;

const DEFAULT_HEALTH_MONITOR_INTERVAL: Duration = Duration::from_secs(30);

#[derive(Debug, Default, Clone, Copy, PartialEq, Eq)]
pub struct HealthMonitorTickSummary {
    pub ensured: usize,
    pub probed: usize,
}

pub struct HealthMonitorHandle {
    shutdown_tx: Option<oneshot::Sender<()>>,
    task: JoinHandle<()>,
}

impl HealthMonitorHandle {
    pub async fn stop(mut self) {
        if let Some(shutdown_tx) = self.shutdown_tx.take() {
            let _ = shutdown_tx.send(());
        }
        let _ = self.task.await;
    }
}

#[derive(Clone)]
pub struct HealthMonitor {
    provider_repo: ProviderRepo,
    health_service: ProviderHealthService,
    interval: Duration,
}

impl HealthMonitor {
    pub fn new(pool: SqlitePool, interval: Duration) -> Self {
        Self {
            provider_repo: ProviderRepo::new(pool.clone()),
            health_service: ProviderHealthService::new(pool),
            interval,
        }
    }

    pub fn with_default_interval(pool: SqlitePool) -> Self {
        Self::new(pool, DEFAULT_HEALTH_MONITOR_INTERVAL)
    }

    pub fn start(self) -> HealthMonitorHandle {
        let (shutdown_tx, mut shutdown_rx) = oneshot::channel();
        let task = tokio::spawn(async move {
            let mut interval = tokio::time::interval(self.interval);
            interval.set_missed_tick_behavior(tokio::time::MissedTickBehavior::Skip);

            loop {
                tokio::select! {
                    _ = interval.tick() => {
                        if let Err(err) = self.run_once().await {
                            eprintln!("fluxd health monitor tick failed: {err}");
                        }
                    }
                    _ = &mut shutdown_rx => {
                        break;
                    }
                }
            }
        });

        HealthMonitorHandle {
            shutdown_tx: Some(shutdown_tx),
            task,
        }
    }

    pub async fn run_once(&self) -> Result<HealthMonitorTickSummary> {
        let providers = self.provider_repo.list().await?;
        let mut summary = HealthMonitorTickSummary::default();

        for provider in providers.into_iter().filter(|provider| provider.enabled) {
            let state = self.health_service.ensure_provider(&provider.id).await?;
            summary.ensured += 1;

            if state.status == "unhealthy" {
                self.health_service.probe_provider(&provider.id).await?;
                summary.probed += 1;
            }
        }

        Ok(summary)
    }
}
