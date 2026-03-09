export type AlertLevel = 'info' | 'warning' | 'error';

export type AlertItem = {
  id: string;
  level: AlertLevel;
  title: string;
  detail: string;
  timestamp: string;
};

type AlertFeedProps = {
  alerts: AlertItem[];
  emptyTitle?: string;
  emptyDescription?: string;
};

function formatAlertLevel(level: AlertLevel): string {
  if (level === 'warning') {
    return 'Warning';
  }
  if (level === 'error') {
    return 'Error';
  }
  return 'Info';
}

export function AlertFeed({
  alerts,
  emptyTitle = 'No alerts yet.',
  emptyDescription = 'Recent provider errors, fallback hits, and gateway warnings will surface here.',
}: AlertFeedProps) {
  if (alerts.length === 0) {
    return (
      <div className="empty-state">
        <p>{emptyTitle}</p>
        <span className="muted">{emptyDescription}</span>
      </div>
    );
  }

  return (
    <ul className="alert-feed" aria-label="Recent alerts">
      {alerts.map((alert) => (
        <li key={alert.id} className="alert-feed__item">
          <div className="alert-feed__header">
            <div>
              <h3>{alert.title}</h3>
              <p className="muted">{alert.timestamp}</p>
            </div>
            <span className={`alert-feed__badge alert-feed__badge--${alert.level}`}>{formatAlertLevel(alert.level)}</span>
          </div>
          <p className="alert-feed__detail">{alert.detail}</p>
        </li>
      ))}
    </ul>
  );
}
