import type { RequestLog } from '../../api/admin';

type LogSectionProps = {
  logs: RequestLog[];
};

export function LogSection({ logs }: LogSectionProps) {
  return (
    <section className="app-card">
      <h2>Logs</h2>
      {logs.length === 0 ? (
        <p className="muted">No logs yet.</p>
      ) : (
        <ul>
          {logs.map((log) => (
            <li key={log.request_id}>
              {log.request_id} ({log.status_code}, {log.latency_ms}ms)
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
