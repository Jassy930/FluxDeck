type MetricCardTone = 'healthy' | 'warning' | 'error';

type MetricCardProps = {
  label: string;
  value: string;
  helper?: string;
  trend?: string;
  tone?: MetricCardTone;
};

export function MetricCard({ label, value, helper, trend, tone = 'healthy' }: MetricCardProps) {
  return (
    <article className={`metric-card metric-card--${tone}`}>
      <span className="metric-card__label">{label}</span>
      <strong>{value}</strong>
      {helper ? <p className="muted">{helper}</p> : null}
      {trend ? <p className="metric-card__trend">{trend}</p> : null}
    </article>
  );
}
