const TIME_FILTERS = ['1m', '5m', '15m', '1h'] as const;

const THROUGHPUT_POINTS = '10,90 60,76 110,80 160,52 210,58 260,22 310,70 360,66';
const LATENCY_POINTS = '10,84 60,86 110,82 160,78 210,44 260,82 310,74 360,28';

export function TrendPanel() {
  return (
    <section className="trend-panel" aria-label="Request throughput and latency trend">
      <div className="trend-panel__header">
        <div>
          <p className="eyebrow">Live metrics</p>
          <h3>Request Throughput</h3>
          <p className="muted">Latency Trend</p>
        </div>
        <div className="trend-panel__filters" aria-label="Time range filters">
          {TIME_FILTERS.map((filter) => (
            <span key={filter} className={`trend-filter ${filter === '15m' ? 'trend-filter--active' : ''}`}>
              {filter}
            </span>
          ))}
        </div>
      </div>
      <div className="trend-panel__body">
        <div className="trend-panel__stats">
          <article>
            <span className="metric-card__label">Request Throughput</span>
            <strong>128 rpm</strong>
            <p className="muted">Traffic remains stable across active gateways</p>
          </article>
          <article>
            <span className="metric-card__label">Latency Trend</span>
            <strong>48 ms</strong>
            <p className="muted">P95 response time stays inside the healthy band</p>
          </article>
        </div>
        <svg className="trend-panel__chart" viewBox="0 0 380 120" role="img" aria-label="Request throughput and latency trend chart">
          <defs>
            <linearGradient id="throughput-fill" x1="0" y1="0" x2="0" y2="1">
              <stop offset="0%" stopColor="rgba(56, 189, 248, 0.35)" />
              <stop offset="100%" stopColor="rgba(56, 189, 248, 0)" />
            </linearGradient>
          </defs>
          <line x1="10" y1="96" x2="370" y2="96" className="trend-panel__axis" />
          <path d="M10 90 L60 76 L110 80 L160 52 L210 58 L260 22 L310 70 L360 66 L360 96 L10 96 Z" className="trend-panel__area" />
          <polyline points={THROUGHPUT_POINTS} className="trend-panel__line trend-panel__line--throughput" />
          <polyline points={LATENCY_POINTS} className="trend-panel__line trend-panel__line--latency" />
          <circle cx="260" cy="22" r="4" className="trend-panel__point trend-panel__point--throughput" />
          <circle cx="360" cy="28" r="4" className="trend-panel__point trend-panel__point--latency" />
        </svg>
      </div>
    </section>
  );
}
