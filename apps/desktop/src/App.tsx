import { AppShell } from './ui/layout/AppShell';
import type { AdminApi, CreateProviderInput } from './api/admin';
import { createAdminApi } from './api/admin';
import { createProviderAndRefresh, ProviderSection } from './ui/providers/ProviderSection';

export async function createProviderFromUi(api: AdminApi, input: CreateProviderInput) {
  return createProviderAndRefresh(api, input);
}

export function App() {
  const api = createAdminApi();
  return (
    <AppShell
      title="FluxDeck Admin"
      sidebar={
        <section>
          <h2>Sidebar</h2>
          <p className="muted">Provider / Gateway / Logs</p>
        </section>
      }
    >
      <ProviderSection providers={[]} onCreate={(input) => createProviderFromUi(api, input).then(() => {})} />

      <section className="app-card">
        <h2>Gateways</h2>
        <p className="muted">No gateways yet.</p>
      </section>

      <section className="app-card">
        <h2>Logs</h2>
        <p className="muted">No logs yet.</p>
      </section>
    </AppShell>
  );
}

export default App;
