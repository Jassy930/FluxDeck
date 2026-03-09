import type { AdminApi, CreateProviderInput, Provider } from '../../api/admin';
import { ProviderForm, submitProviderForm } from '../../components/ProviderForm';

type ProviderSectionProps = {
  providers: Provider[];
  error?: string | null;
  onCreate: (input: CreateProviderInput) => Promise<void> | void;
};

export function ProviderSection({ providers, error, onCreate }: ProviderSectionProps) {
  return (
    <section className="app-card settings-section" id="providers">
      <div className="section-heading">
        <div>
          <p className="eyebrow">Provider Settings</p>
          <h2>Providers</h2>
          <p className="muted">
            Manage upstream model endpoints, credentials, and the model catalog exposed to gateways.
          </p>
        </div>
        <span className="count-pill">{providers.length} configured</span>
      </div>
      {error ? <p className="form-message form-message--error">{error}</p> : null}
      <div className="settings-section__content">
        <ProviderForm onSubmit={onCreate} />
        <div className="resource-pane">
          <div className="section-heading section-heading--compact">
            <div>
              <p className="eyebrow">Inventory</p>
              <h3>Configured providers</h3>
            </div>
          </div>
          {providers.length === 0 ? (
            <div className="empty-state">
              <p>No providers yet.</p>
              <span className="muted">Create a provider to connect your upstream LLM service.</span>
            </div>
          ) : (
            <ul className="resource-list">
              {providers.map((provider) => (
                <li key={provider.id} className="resource-card">
                  <div className="resource-card__header">
                    <div>
                      <h3>{provider.name}</h3>
                      <p className="muted">{provider.id}</p>
                    </div>
                    <span
                      className={`status-badge ${provider.enabled ? 'status-badge--running' : 'status-badge--stopped'}`}
                    >
                      {provider.enabled ? 'Enabled' : 'Disabled'}
                    </span>
                  </div>
                  <div className="pill-row">
                    <span className="info-pill">{provider.kind}</span>
                    <span className="info-pill">{provider.models?.length ?? 0} models</span>
                  </div>
                  <p className="resource-card__meta">{provider.base_url}</p>
                </li>
              ))}
            </ul>
          )}
        </div>
      </div>
    </section>
  );
}

export async function createProviderAndRefresh(
  api: AdminApi,
  input: CreateProviderInput,
): Promise<Provider[]> {
  await submitProviderForm(api, input);
  return api.listProviders();
}
