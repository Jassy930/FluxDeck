import { useEffect, useState } from 'react';
import { AlertFeed } from './AlertFeed';
import { MetricCard } from './MetricCard';
import { TrendPanel } from './TrendPanel';
import type { AdminApi, StatsOverview } from '../../api/admin';

type MonitorPageProps = {
  api: AdminApi;
  providerCount: number;
  gatewayCount: number;
  runningGatewayCount: number;
  errorGatewayCount: number;
  error?: string | null;
};

export function MonitorPage({
  api,
  providerCount,
  gatewayCount,
  runningGatewayCount,
  errorGatewayCount,
  error,
}: MonitorPageProps) {
  const [stats, setStats] = useState<StatsOverview | null>(null);
  const [statsLoading, setStatsLoading] = useState(true);
  const [statsError, setStatsError] = useState<string | null>(null);
  const [selectedPeriod, setSelectedPeriod] = useState('1h');

  // Fetch stats overview
  useEffect(() => {
    let mounted = true;
    async function fetchStats() {
      try {
        setStatsLoading(true);
        setStatsError(null);
        const data = await api.getStatsOverview(selectedPeriod);
        if (mounted) {
          setStats(data);
        }
      } catch (err) {
        if (mounted) {
          setStatsError(err instanceof Error ? err.message : 'Failed to load stats');
        }
      } finally {
        if (mounted) {
          setStatsLoading(false);
        }
      }
    }
    fetchStats();
    return () => {
      mounted = false;
    };
  }, [api, selectedPeriod]);

  // Generate alerts based on actual stats
  const alerts = [
    {
      id: 'alert-warmup',
      level: 'info' as const,
      title: 'Gateway warmup completed',
      detail: `${runningGatewayCount} of ${gatewayCount} gateways are running and ready for traffic.`,
      timestamp: 'just now',
    },
    {
      id: 'alert-latency',
      level: stats && stats.by_gateway?.some(g => g.avg_latency > 1000)
        ? ('warning' as const)
        : ('info' as const),
      title: stats && stats.by_gateway?.some(g => g.avg_latency > 1000)
        ? 'Latency elevated'
        : 'Latency remains stable',
      detail:
        stats && stats.by_gateway?.some(g => g.avg_latency > 1000)
          ? 'One or more gateways showing P95 latency above 1s threshold.'
          : 'Gateway response times remain within acceptable bounds.',
      timestamp: '2m ago',
    },
    {
      id: 'alert-errors',
      level: stats && stats.error_requests > 0 ? ('error' as const) : ('info' as const),
      title: stats && stats.error_requests > 0 ? 'Request errors detected' : 'Request flow healthy',
      detail:
        stats && stats.error_requests > 0
          ? `${stats.error_requests} failed requests in the selected period. Check logs for details.`
          : 'All requests completing successfully with no recent errors.',
      timestamp: '5m ago',
    },
  ];

  // Calculate derived metrics from stats
  const requestsPerMin = stats?.requests_per_minute ?? 0;
  const avgLatency = stats?.by_gateway?.length
    ? Math.round(
        stats.by_gateway.reduce((sum, g) => sum + (g.avg_latency || 0), 0) /
        stats.by_gateway.length
      )
    : 0;

  return (
    <>
      <section className="app-card overview-card" id="overview">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Monitor</p>
            <h2>Monitor overview</h2>
            <p className="muted">
              Watch gateway health, request throughput, latency, and alerts from one desktop
              workspace.
            </p>
          </div>
          <div className="time-filter-group">
            {(['1h', '6h', '24h'] as const).map((p) => (
              <span
                key={p}
                className={`trend-filter ${selectedPeriod === p ? 'trend-filter--active' : ''}`}
                onClick={() => setSelectedPeriod(p)}
              >
                {p}
              </span>
            ))}
          </div>
        </div>
        {error ? <p className="form-message form-message--error">{error}</p> : null}
        {statsError ? (
          <p className="form-message form-message--error">{statsError}</p>
        ) : null}
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
            value={statsLoading ? '...' : String(Math.round(requestsPerMin))}
            helper="Average requests per minute"
            trend={
              statsLoading
                ? 'Loading...'
                : stats?.total_requests === 0
                  ? 'No recent traffic'
                  : `${stats?.total_requests ?? 0} total requests`
            }
          />
          <MetricCard
            label="P95 Latency"
            value={statsLoading ? '...' : `${avgLatency} ms`}
            helper="Average response time"
            trend={
              statsLoading
                ? 'Loading...'
                : avgLatency < 200
                  ? 'Fast response times'
                  : avgLatency < 1000
                    ? 'Moderate latency'
                    : 'Latency elevated'
            }
            tone={avgLatency < 200 ? 'healthy' : avgLatency < 1000 ? undefined : 'error'}
          />
        </div>
      </section>

      <section className="app-card settings-section">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Traffic</p>
            <h2>Gateway Runtime Board</h2>
            <p className="muted">
              Track runtime capacity, active routes, and recent movement across the local stack.
            </p>
          </div>
          <span className="count-pill">{gatewayCount} gateways</span>
        </div>
        <div className="monitor-runtime-grid">
          <TrendPanel api={api} period={selectedPeriod} />
          <article className="metric-card metric-card--healthy">
            <span className="metric-card__label">Token Usage</span>
            <strong>{statsLoading ? '...' : formatNumber(stats?.total_tokens ?? 0)}</strong>
            <p className="muted">Total tokens processed in selected period</p>
            <p className="metric-card__trend">
              {stats?.total_tokens === 0
                ? 'No tokens consumed yet'
                : `${formatNumber(stats?.total_tokens ?? 0)} tokens used`}
            </p>
          </article>
        </div>
      </section>

      <section className="app-card settings-section">
        <div className="section-heading">
          <div>
            <p className="eyebrow">Alerts</p>
            <h2>Recent Alerts</h2>
            <p className="muted">
              A running feed of warnings, fallback events, and request failures will appear here.
            </p>
          </div>
          <span className="count-pill">
            {stats?.error_requests ?? 0} active issues
          </span>
        </div>
        <AlertFeed alerts={alerts} />
      </section>

      {/* Stats breakdown by gateway/provider */}
      {(stats?.by_gateway?.length ?? 0) > 0 || (stats?.by_provider?.length ?? 0) > 0 ? (
        <section className="app-card settings-section">
          <div className="section-heading">
            <div>
              <p className="eyebrow">Breakdown</p>
              <h2>Statistics by Dimension</h2>
              <p className="muted">View request distribution across gateways and providers.</p>
            </div>
          </div>
          <div className="stats-breakdown-grid">
            {stats?.by_gateway?.map((g) => (
              <article key={g.gateway_id} className="metric-card">
                <span className="metric-card__label">{g.gateway_id}</span>
                <strong>{g.request_count} req</strong>
                <p className="muted">{g.avg_latency}ms avg / {g.error_count} errors</p>
                <p className="metric-card__trend">
                  {g.total_tokens > 0 ? `${formatNumber(g.total_tokens)} tokens` : 'No tokens'}
                </p>
              </article>
            ))}
          </div>
        </section>
      ) : null}
    </>
  );
}

function formatNumber(num: number): string {
  if (num >= 1_000_000) {
    return `${(num / 1_000_000).toFixed(1)}M`;
  }
  if (num >= 1_000) {
    return `${(num / 1_000).toFixed(1)}K`;
  }
  return String(num);
}
