use std::time::{Duration, SystemTime, UNIX_EPOCH};

use anyhow::Result;
use reqwest::StatusCode;
use sqlx::SqlitePool;
use tokio::sync::oneshot;
use tokio::task::JoinHandle;

use crate::domain::provider::Provider;
use crate::repo::provider_repo::ProviderRepo;
use crate::service::provider_health_service::ProviderHealthService;

const DEFAULT_HEALTH_MONITOR_INTERVAL: Duration = Duration::from_secs(30);
const DEFAULT_PROBE_TIMEOUT: Duration = Duration::from_secs(5);

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
    client: reqwest::Client,
}

impl HealthMonitor {
    pub fn new(pool: SqlitePool, interval: Duration) -> Self {
        Self {
            provider_repo: ProviderRepo::new(pool.clone()),
            health_service: ProviderHealthService::new(pool),
            interval,
            client: reqwest::Client::builder()
                .timeout(DEFAULT_PROBE_TIMEOUT)
                .build()
                .expect("build health monitor client"),
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
            self.health_service.ensure_provider(&provider.id).await?;
            summary.ensured += 1;

            let due_states = self
                .health_service
                .states_for_provider(&provider.id)
                .await?
                .into_iter()
                .filter(|state| {
                    state.status == "unhealthy" && recover_after_due(state.recover_after.as_deref())
                })
                .collect::<Vec<_>>();

            if due_states.is_empty() {
                continue;
            }

            self.run_probe(&provider, &due_states).await?;
            summary.probed += 1;
        }

        Ok(summary)
    }

    async fn run_probe(
        &self,
        provider: &Provider,
        due_states: &[crate::domain::provider_health::ProviderHealthState],
    ) -> Result<()> {
        match self
            .client
            .get(&provider.base_url)
            .bearer_auth(&provider.api_key)
            .send()
            .await
        {
            Ok(response) if probe_success(response.status()) => {
                for state in due_states {
                    self.health_service
                        .mark_probe_result_for_state(state, true, None)
                        .await?;
                }
            }
            Ok(response) => {
                let failure_reason = format!("probe status {}", response.status().as_u16());
                for state in due_states {
                    self.health_service
                        .mark_probe_result_for_state(state, false, Some(&failure_reason))
                        .await?;
                }
            }
            Err(err) => {
                let failure_reason = err.to_string();
                for state in due_states {
                    self.health_service
                        .mark_probe_result_for_state(state, false, Some(&failure_reason))
                        .await?;
                }
            }
        }

        Ok(())
    }
}

fn probe_success(status: StatusCode) -> bool {
    !(status.is_server_error() || status == StatusCode::TOO_MANY_REQUESTS)
}

fn recover_after_due(recover_after: Option<&str>) -> bool {
    let Some(recover_after) = recover_after else {
        return true;
    };

    recover_after
        .parse::<u128>()
        .map(|deadline| deadline <= now_nanos())
        .unwrap_or(true)
}

fn now_nanos() -> u128 {
    SystemTime::now()
        .duration_since(UNIX_EPOCH)
        .map(|duration| duration.as_nanos())
        .unwrap_or(0)
}
