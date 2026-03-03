import type { AdminApi, CreateGatewayInput, Gateway } from '../../api/admin';
import { GatewayForm, submitGatewayForm } from '../../components/GatewayForm';

type GatewaySectionProps = {
  gateways: Gateway[];
  error?: string | null;
  onCreate?: (input: CreateGatewayInput) => Promise<void> | void;
};

export function GatewaySection({ gateways, error, onCreate }: GatewaySectionProps) {
  return (
    <section className="app-card">
      <h2>Gateways</h2>
      {onCreate ? <GatewayForm onSubmit={onCreate} /> : null}
      {error ? <p className="muted">{error}</p> : null}
      {gateways.length === 0 ? (
        <p className="muted">No gateways yet.</p>
      ) : (
        <ul>
          {gateways.map((gateway) => (
            <li key={gateway.id}>
              {gateway.name}
              {` | Runtime: ${gateway.runtime_status ?? 'unknown'}`}
              {gateway.last_error ? ` | Last error: ${gateway.last_error}` : ''}
            </li>
          ))}
        </ul>
      )}
    </section>
  );
}

export async function createGatewayAndRefresh(
  api: AdminApi,
  input: CreateGatewayInput,
): Promise<Gateway[]> {
  await submitGatewayForm(api, input);
  return api.listGateways();
}
