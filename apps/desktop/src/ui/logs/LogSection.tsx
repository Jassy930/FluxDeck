import type { RequestLog } from '../../api/admin';

type LogSectionProps = {
  logs: RequestLog[];
};

export function LogSection({ logs }: LogSectionProps) {
  return (
    <section className="app-card settings-section" id="logs">
      <div className="section-heading">
        <div>
          <p className="eyebrow">Activity Logs</p>
          <h2>Recent requests</h2>
          <p className="muted">Track recent request outcomes, latency, and the provider/gateway pair used.</p>
        </div>
        <span className="count-pill">{logs.length} entries</span>
      </div>
      {logs.length === 0 ? (
        <div className="empty-state">
          <p>No logs yet.</p>
          <span className="muted">Requests routed through FluxDeck will appear here.</span>
        </div>
      ) : (
        <ul className="resource-list resource-list--logs">
          {logs.map((log) => (
            <li key={log.request_id} className="resource-card resource-card--log">
              <div className="resource-card__header">
                <div>
                  <h3>{log.request_id}</h3>
                  <p className="muted">{log.gateway_id} → {log.provider_id}</p>
                </div>
                <span className={`status-badge ${log.error ? 'status-badge--error' : 'status-badge--running'}`}>
                  {log.status_code}
                </span>
              </div>
              <div className="pill-row">
                <span className="info-pill">{log.model ?? 'unknown model'}</span>
                <span className="info-pill">{log.latency_ms}ms</span>
              </div>
              <p className="resource-card__meta">{log.created_at}</p>
              {log.error ? <p className="resource-card__error">{log.error}</p> : null}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
