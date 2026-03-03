import { useEffect, useMemo, useState } from 'react';
import { AppShell } from './ui/layout/AppShell';
import type {
  AdminApi,
  CreateGatewayInput,
  CreateProviderInput,
  DashboardLists,
} from './api/admin';
import { createAdminApi, listDashboardLists } from './api/admin';
import { ProviderSection } from './ui/providers/ProviderSection';
import { GatewaySection } from './ui/gateways/GatewaySection';
import { LogSection } from './ui/logs/LogSection';
import { submitProviderForm } from './components/ProviderForm';
import { submitGatewayForm } from './components/GatewayForm';

type DashboardState = DashboardLists;

const EMPTY_DASHBOARD: DashboardState = {
  providers: [],
  gateways: [],
  logs: [],
};

export async function createProviderFromUi(api: AdminApi, input: CreateProviderInput) {
  await submitProviderForm(api, input);
  return refreshAll(api);
}

export async function createGatewayFromUi(api: AdminApi, input: CreateGatewayInput) {
  await submitGatewayForm(api, input);
  return refreshAll(api);
}

export async function refreshAll(api: AdminApi): Promise<DashboardState> {
  return listDashboardLists(api);
}

export function App() {
  const api = useMemo(() => createAdminApi(), []);
  const [dashboard, setDashboard] = useState<DashboardState>(EMPTY_DASHBOARD);
  const [loadError, setLoadError] = useState<string | null>(null);

  useEffect(() => {
    let cancelled = false;
    void refreshAll(api)
      .then((data) => {
        if (cancelled) {
          return;
        }
        setDashboard(data);
        setLoadError(null);
      })
      .catch((error: unknown) => {
        if (cancelled) {
          return;
        }
        setLoadError(error instanceof Error ? error.message : 'failed to load dashboard');
      });

    return () => {
      cancelled = true;
    };
  }, [api]);

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
      <ProviderSection
        providers={dashboard.providers}
        error={loadError}
        onCreate={(input) =>
          createProviderFromUi(api, input)
            .then((next) => {
              setDashboard(next);
              setLoadError(null);
            })
            .catch((error: unknown) => {
              setLoadError(error instanceof Error ? error.message : 'failed to create provider');
            })
        }
      />
      <GatewaySection
        gateways={dashboard.gateways}
        error={loadError}
        onCreate={(input) =>
          createGatewayFromUi(api, input)
            .then((next) => {
              setDashboard(next);
              setLoadError(null);
            })
            .catch((error: unknown) => {
              setLoadError(error instanceof Error ? error.message : 'failed to create gateway');
            })
        }
      />
      <LogSection logs={dashboard.logs} />
    </AppShell>
  );
}

export default App;
