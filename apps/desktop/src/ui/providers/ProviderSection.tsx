import type { AdminApi, CreateProviderInput, Provider } from '../../api/admin';
import { ProviderForm, submitProviderForm } from '../../components/ProviderForm';

type ProviderSectionProps = {
  providers: Provider[];
  error?: string | null;
  onCreate: (input: CreateProviderInput) => Promise<void> | void;
};

export function ProviderSection({ providers, error, onCreate }: ProviderSectionProps) {
  return (
    <section className="app-card">
      <h2>Providers</h2>
      <ProviderForm onSubmit={onCreate} />
      {error ? <p className="muted">{error}</p> : null}
      {providers.length === 0 ? (
        <p className="muted">No providers yet.</p>
      ) : (
        <ul>
          {providers.map((provider) => (
            <li key={provider.id}>
              {provider.name} ({provider.kind})
            </li>
          ))}
        </ul>
      )}
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
