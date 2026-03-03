import type { Gateway } from '../../api/admin';

type GatewaySectionProps = {
  gateways: Gateway[];
};

export function GatewaySection({ gateways }: GatewaySectionProps) {
  return (
    <section className="app-card">
      <h2>Gateways</h2>
      {gateways.length === 0 ? (
        <p className="muted">No gateways yet.</p>
      ) : (
        <ul>
          {gateways.map((gateway) => (
            <li key={gateway.id}>
              {gateway.name} ({gateway.runtime_status ?? 'unknown'})
              {gateway.last_error ? ` - error: ${gateway.last_error}` : ''}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}
