import { AlertFeed } from './AlertFeed';
import { MetricCard } from './MetricCard';
import { TrendPanel } from './TrendPanel';

type MonitorPageProps = {
  providerCount: number;
  gatewayCount: number;
  runningGatewayCount: number;
  errorGatewayCount: number;
  logCount: number;
  error?: string | null;
};

export function MonitorPage({
  providerCount,
  gatewayCount,
  runningGatewayCount,
  errorGatewayCount,
  logCount,
  error,
}: MonitorPageProps) {
  const alerts = [
    {
      id: 'alert-warmup',
      level: 'info' as const,
      title: 'Gateway warmup completed',
      detail: 'gateway_main finished startup checks and is ready for local traffic.',
      timestamp: 'just now',
    },
    {
      id: 'alert-latency',
      level: errorGatewayCount > 0 ? ('warning' as const) : ('info' as const),
      title: errorGatewayCount > 0 ? 'Latency increased' : 'Latency remains stable',
      detail:
        errorGatewayCount > 0
          ? 'P95 latency climbed above the target band on one or more gateway routes.'
          : 'Gateway response times remain inside the target band.',
      timestamp: '2m ago',
    },
    {
      id: 'alert-provider',
      level: errorGatewayCount > 0 ? ('error' as const) : ('info' as const),
      title: errorGatewayCount > 0 ? 'Provider timeout' : 'Provider pool healthy',
      detail:
        errorGatewayCount > 0
          ? 'provider_main timed out during upstream failover and needs operator attention.'
          : 'Active providers are responding normally with no recent upstream failures.',
      timestamp: '5m ago',
    },
  ];

  return (
    <>
      <section className="app-card overview-card" id="overview">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Monitor</p>
            <h2>Monitor overview</h2>
            <p className="muted">Watch gateway health, request throughput, latency, and alerts from one desktop workspace.</p>
          </div>
          <span className="info-pill">Live status</span>
        </div>
        {error ? <p className="form-message form-message--error">{error}</p> : null}
        <div className="overview-metrics">
          <MetricCard
            label="Running Gateways"
            value={String(runningGatewayCount)}
            helper="Gateways currently serving traffic"
            trend={gatewayCount === 0 ? 'No active routes yet' : `${gatewayCount} routes active`}
            tone={errorGatewayCount > 0 ? 'warning' : 'healthy'}
          />
          <MetricCard
            label="Active Providers"
            value={String(providerCount)}
            helper="Configured upstream providers"
            trend={providerCount === 0 ? 'Awaiting provider setup' : `${providerCount} providers ready`}
          />
          <MetricCard
            label="Requests / min"
            value={String(logCount)}
            helper="Latest request volume snapshot"
            trend={logCount === 0 ? 'No recent traffic' : `${logCount} recent requests observed`}
          />
          <MetricCard
            label="P95 Latency"
            value={errorGatewayCount === 0 ? '48 ms' : '132 ms'}
            helper="High percentile response time estimate"
            trend={errorGatewayCount === 0 ? 'Stable latency window' : 'Latency elevated by errors'}
            tone={errorGatewayCount === 0 ? 'healthy' : 'error'}
          />
        </div>
      </section>
      <section className="app-card settings-section">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Traffic</p>
            <h2>Gateway Runtime Board</h2>
            <p className="muted">Track runtime capacity, active routes, and recent movement across the local stack.</p>
          </div>
          <span className="count-pill">{gatewayCount} gateways</span>
        </div>
        <div className="monitor-runtime-grid">
          <TrendPanel />
          <article className="metric-card metric-card--healthy">
            <span className="metric-card__label">Provider Health</span>
            <strong>Healthy</strong>
            <p className="muted">Provider latency and availability summary placeholder</p>
            <p className="metric-card__trend">{providerCount} providers in the active pool</p>
          </article>
        </div>
      </section>
      <section className="app-card settings-section">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Alerts</p>
            <h2>Recent Alerts</h2>
            <p className="muted">A running feed of warnings, fallback events, and request failures will appear here.</p>
          </div>
          <span className="count-pill">{errorGatewayCount} active issues</span>
        </div>
        <AlertFeed alerts={alerts} />
      </section>
    </>
  );
}
