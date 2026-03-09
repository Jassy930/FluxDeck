import type { AdminApi, CreateGatewayInput, Gateway } from '../../api/admin';
import { GatewayForm, submitGatewayForm } from '../../components/GatewayForm';

type GatewaySectionProps = {
  gateways: Gateway[];
  error?: string | null;
  onCreate?: (input: CreateGatewayInput) => Promise<void> | void;
};

function getGatewayStatusClass(runtimeStatus?: string | null): string {
  if (runtimeStatus === 'running') {
    return 'status-badge status-badge--running';
  }
  if (runtimeStatus === 'error') {
    return 'status-badge status-badge--error';
  }
  return 'status-badge status-badge--stopped';
}

export function GatewaySection({ gateways, error, onCreate }: GatewaySectionProps) {
  return (
    <section className="app-card settings-section" id="gateways">
      <div className="section-heading">
        <div>
          <p className="eyebrow">Gateway Settings</p>
          <h2>Gateways</h2>
          <p className="muted">
            Configure local endpoints, upstream protocols, and runtime defaults for each compatible gateway.
          </p>
        </div>
        <span className="count-pill">{gateways.length} configured</span>
      </div>
      {error ? <p className="form-message form-message--error">{error}</p> : null}
      <div className="settings-section__content">
        {onCreate ? <GatewayForm onSubmit={onCreate} /> : null}
        <div className="resource-pane">
          <div className="section-heading section-heading--compact">
            <div>
              <p className="eyebrow">Runtime</p>
              <h3>Gateway status board</h3>
            </div>
          </div>
          {gateways.length === 0 ? (
            <div className="empty-state">
              <p>No gateways yet.</p>
              <span className="muted">Create a gateway to expose a local API endpoint.</span>
            </div>
          ) : (
            <ul className="resource-list">
              {gateways.map((gateway) => (
                <li key={gateway.id} className="resource-card">
                  <div className="resource-card__header">
                    <div>
                      <h3>{gateway.name}</h3>
                      <p className="muted">{gateway.id}</p>
                    </div>
                    <span className={getGatewayStatusClass(gateway.runtime_status)}>
                      Runtime: {gateway.runtime_status ?? 'unknown'}
                    </span>
                  </div>
                  <div className="pill-row">
                    <span className="info-pill">{gateway.listen_host}:{gateway.listen_port}</span>
                    <span className="info-pill">{gateway.inbound_protocol} → {gateway.upstream_protocol}</span>
                  </div>
                  <p className="resource-card__meta">Default provider: {gateway.default_provider_id}</p>
                  {gateway.default_model ? (
                    <p className="resource-card__meta">Default model: {gateway.default_model}</p>
                  ) : null}
                  {gateway.last_error ? (
                    <p className="resource-card__error">Last error: {gateway.last_error}</p>
                  ) : null}
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
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
