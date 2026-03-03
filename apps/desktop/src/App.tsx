import { useEffect, useMemo, useState } from 'react';
import { AppShell } from './ui/layout/AppShell';
import type { AdminApi, CreateProviderInput } from './api/admin';
import { createAdminApi } from './api/admin';
import { createProviderAndRefresh, ProviderSection } from './ui/providers/ProviderSection';
import { GatewaySection } from './ui/gateways/GatewaySection';
import { LogSection } from './ui/logs/LogSection';

type DashboardState = {
  providers: Awaited<ReturnType<AdminApi['listProviders']>>;
  gateways: Awaited<ReturnType<AdminApi['listGateways']>>;
  logs: Awaited<ReturnType<AdminApi['listLogs']>>;
};

const EMPTY_DASHBOARD: DashboardState = {
  providers: [],
  gateways: [],
  logs: [],
};

export async function createProviderFromUi(api: AdminApi, input: CreateProviderInput) {
  return createProviderAndRefresh(api, input);
}

export async function refreshAll(api: AdminApi): Promise<DashboardState> {
  const [providers, gateways, logs] = await Promise.all([
    api.listProviders(),
    api.listGateways(),
    api.listLogs(),
  ]);
  return { providers, gateways, logs };
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
            .then((providers) => {
              setDashboard((prev) => ({ ...prev, providers }));
              setLoadError(null);
            })
            .catch((error: unknown) => {
              setLoadError(error instanceof Error ? error.message : 'failed to create provider');
            })
        }
      />
      <GatewaySection gateways={dashboard.gateways} />
      <LogSection logs={dashboard.logs} />
    </AppShell>
  );
}

export default App;
