import { useEffect, useState } from 'react';
import type { AdminApi, StatsTrend, StatsTrendPoint } from '../../api/admin';

type TrendPanelProps = {
  api: AdminApi;
  period?: string;
  interval?: string;
};

export function TrendPanel({ api, period = '1h', interval = '5m' }: TrendPanelProps) {
  const [trend, setTrend] = useState<StatsTrend | null>(null);
  const [loading, setLoading] = useState(true);
  const [error, setError] = useState<string | null>(null);
  const [selectedFilter, setSelectedFilter] = useState('15m');

  useEffect(() => {
    let mounted = true;
    async function fetchTrend() {
      try {
        setLoading(true);
        setError(null);
        const data = await api.getStatsTrend(period, interval);
        if (mounted) {
          setTrend(data);
        }
      } catch (err) {
        if (mounted) {
          setError(err instanceof Error ? err.message : 'Failed to load trend');
        }
      } finally {
        if (mounted) {
          setLoading(false);
        }
      }
    }
    fetchTrend();
    return () => {
      mounted = false;
    };
  }, [api, period, interval]);

  // Calculate summary stats from trend data
  const summary = trend?.data?.reduce(
    (acc, point) => ({
      totalRequests: acc.totalRequests + (point.request_count ?? 0),
      totalLatency: acc.totalLatency + (point.avg_latency ?? 0),
      pointCount: acc.pointCount + 1,
      maxRequests: Math.max(acc.maxRequests, point.request_count ?? 0),
      minLatency: Math.min(acc.minLatency, point.avg_latency ?? Infinity),
      maxLatency: Math.max(acc.maxLatency, point.avg_latency ?? 0),
    }),
    {
      totalRequests: 0,
      totalLatency: 0,
      pointCount: 0,
      maxRequests: 0,
      minLatency: Infinity,
      maxLatency: 0,
    }
  ) ?? {
    totalRequests: 0,
    totalLatency: 0,
    pointCount: 0,
    maxRequests: 0,
    minLatency: Infinity,
    maxLatency: 0,
  };

  const avgRequests = summary.pointCount > 0 ? Math.round(summary.totalRequests / summary.pointCount) : 0;
  const avgLatency = summary.pointCount > 0 ? Math.round(summary.totalLatency / summary.pointCount) : 0;

  // Generate chart points from trend data
  const chartPoints = generateChartPoints(trend?.data ?? []);

  return (
    <section className="trend-panel" aria-label="Request throughput and latency trend">
      <div className="trend-panel__header">
        <div>
          <p className="eyebrow">Live metrics</p>
          <h3>Request Throughput</h3>
          <p className="muted">Latency Trend</p>
        </div>
        <div className="trend-panel__filters" aria-label="Time range filters">
          {['1m', '5m', '15m', '1h'].map((filter) => (
            <span
              key={filter}
              className={`trend-filter ${selectedFilter === filter ? 'trend-filter--active' : ''}`}
              onClick={() => setSelectedFilter(filter)}
            >
              {filter}
            </span>
          ))}
        </div>
      </div>
      {error ? (
        <div className="trend-panel__body">
          <p className="form-message form-message--error">{error}</p>
        </div>
      ) : (
        <div className="trend-panel__body">
          <div className="trend-panel__stats">
            <article>
              <span className="metric-card__label">Request Throughput</span>
              <strong>{loading ? '...' : `${avgRequests} rpm`}</strong>
              <p className="muted">
                {loading
                  ? 'Loading...'
                  : trend?.data?.length === 0
                    ? 'No traffic in this period'
                    : `${summary.totalRequests} total requests`}
              </p>
            </article>
            <article>
              <span className="metric-card__label">Latency Trend</span>
              <strong>{loading ? '...' : `${avgLatency} ms`}</strong>
              <p className="muted">
                {loading
                  ? 'Loading...'
                  : summary.maxLatency === 0
                    ? 'No latency data'
                    : `${summary.minLatency}-${summary.maxLatency} ms range`}
              </p>
            </article>
          </div>
          {loading ? (
            <div className="trend-panel__loading">
              <p className="muted">Loading trend data...</p>
            </div>
          ) : chartPoints.throughput || chartPoints.latency ? (
            <svg
              className="trend-panel__chart"
              viewBox="0 0 380 120"
              role="img"
              aria-label="Request throughput and latency trend chart"
            >
              <defs>
                <linearGradient id="throughput-fill" x1="0" y1="0" x2="0" y2="1">
                  <stop offset="0%" stopColor="rgba(56, 189, 248, 0.35)" />
                  <stop offset="100%" stopColor="rgba(56, 189, 248, 0)" />
                </linearGradient>
              </defs>
              <line x1="10" y1="96" x2="370" y2="96" className="trend-panel__axis" />
              {chartPoints.area && <path d={chartPoints.area} className="trend-panel__area" />}
              {chartPoints.throughput && (
                <polyline
                  points={chartPoints.throughput}
                  className="trend-panel__line trend-panel__line--throughput"
                />
              )}
              {chartPoints.latency && (
                <polyline
                  points={chartPoints.latency}
                  className="trend-panel__line trend-panel__line--latency"
                />
              )}
              {chartPoints.highlightThroughput && (
                <circle
                  cx={chartPoints.highlightThroughput.x}
                  cy={chartPoints.highlightThroughput.y}
                  r="4"
                  className="trend-panel__point trend-panel__point--throughput"
                />
              )}
              {chartPoints.highlightLatency && (
                <circle
                  cx={chartPoints.highlightLatency.x}
                  cy={chartPoints.highlightLatency.y}
                  r="4"
                  className="trend-panel__point trend-panel__point--latency"
                />
              )}
            </svg>
          ) : (
            <div className="trend-panel__empty">
              <p className="muted">No trend data available for the selected period</p>
            </div>
          )}
        </div>
      )}
    </section>
  );
}

function generateChartPoints(data: StatsTrendPoint[]): {
  throughput: string;
  latency: string;
  area: string;
  highlightThroughput: { x: number; y: number } | null;
  highlightLatency: { x: number; y: number } | null;
} {
  if (!data || data.length === 0) {
    return { throughput: '', latency: '', area: '', highlightThroughput: null, highlightLatency: null };
  }

  const chartWidth = 360;
  const chartHeight = 86;
  const padding = 10;
  const maxRequests = Math.max(...data.map((d) => d.request_count ?? 0), 1);
  const maxLatency = Math.max(...data.map((d) => d.avg_latency ?? 1), 1);

  const xStep = chartWidth / Math.max(data.length - 1, 1);

  const throughputPoints: string[] = [];
  const latencyPoints: string[] = [];
  const areaPoints: string[] = [];

  data.forEach((point, i) => {
    const x = padding + i * xStep;
    const requestY = chartHeight + padding - ((point.request_count ?? 0) / maxRequests) * chartHeight;
    const latencyY = chartHeight + padding - ((point.avg_latency ?? 1) / maxLatency) * chartHeight;

    throughputPoints.push(`${x},${requestY}`);
    latencyPoints.push(`${x},${latencyY}`);
    areaPoints.push(`${x},${requestY}`);
  });

  // Create area path
  const areaPath =
    areaPoints.length > 0
      ? `M ${areaPoints[0]} L ${areaPoints.slice(1).join(' L ')} L ${areaPoints[areaPoints.length - 1].split(',')[0]},${chartHeight + padding} L ${padding},${chartHeight + padding} Z`
      : '';

  // Find highlight points (last point with data)
  const lastIdx = data.length - 1;
  const highlightThroughput =
    data[lastIdx]?.request_count !== undefined
      ? {
          x: padding + lastIdx * xStep,
          y: chartHeight + padding - ((data[lastIdx].request_count ?? 1) / maxRequests) * chartHeight,
        }
      : null;

  const highlightLatency =
    data[lastIdx]?.avg_latency !== undefined
      ? {
          x: padding + lastIdx * xStep,
          y: chartHeight + padding - ((data[lastIdx].avg_latency ?? 1) / maxLatency) * chartHeight,
        }
      : null

  return {
    throughput: throughputPoints.join(' '),
    latency: latencyPoints.join(' '),
    area: areaPath,
    highlightThroughput,
    highlightLatency,
  };
}
