import { useCallback, useEffect, useMemo, useState } from 'react';
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
import { MonitorPage } from './ui/monitor/MonitorPage';
import { TopologyPage } from './ui/topology/TopologyPage';
import { submitProviderForm } from './components/ProviderForm';
import { submitGatewayForm } from './components/GatewayForm';

type DashboardState = DashboardLists;
type AppPage = 'monitor' | 'topology' | 'providers' | 'gateways' | 'logs';

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

type AppProps = {
  initialPage?: AppPage;
};

export function App({ initialPage = 'monitor' }: AppProps) {
  const api = useMemo(() => createAdminApi(), []);
  const [dashboard, setDashboard] = useState<DashboardState>(EMPTY_DASHBOARD);
  const [currentPage, setCurrentPage] = useState<AppPage>(initialPage);
  const [loadError, setLoadError] = useState<string | null>(null);
  const [isRefreshing, setIsRefreshing] = useState(false);

  const handleRefresh = useCallback(async () => {
    setIsRefreshing(true);
    try {
      const data = await refreshAll(api);
      setDashboard(data);
      setLoadError(null);
    } catch (error: unknown) {
      setLoadError(error instanceof Error ? error.message : 'failed to load dashboard');
    } finally {
      setIsRefreshing(false);
    }
  }, [api]);

  useEffect(() => {
    void handleRefresh();
  }, [handleRefresh]);

  const runningGateways = dashboard.gateways.filter((gateway) => gateway.runtime_status === 'running').length;
  const errorGateways = dashboard.gateways.filter((gateway) => gateway.runtime_status === 'error').length;

  const providerSection = (
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
  );

  const gatewaySection = (
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
  );

  const logSection = <LogSection logs={dashboard.logs} />;

  let pageContent = (
    <MonitorPage
      providerCount={dashboard.providers.length}
      gatewayCount={dashboard.gateways.length}
      runningGatewayCount={runningGateways}
      errorGatewayCount={errorGateways}
      logCount={dashboard.logs.length}
      error={loadError}
    />
  );

  if (currentPage === 'topology') {
    pageContent = <TopologyPage />;
  }

  if (currentPage === 'providers') {
    pageContent = providerSection;
  }

  if (currentPage === 'gateways') {
    pageContent = gatewaySection;
  }

  if (currentPage === 'logs') {
    pageContent = logSection;
  }

  return (
    <AppShell
      title="FluxDeck Admin"
      subtitle="Monitor-first workspace for local provider, gateway, and request-log operations."
      headerMeta={
        <div className="metric-strip" aria-label="Resource summary">
          <span className="metric-pill">{dashboard.providers.length} Providers</span>
          <span className="metric-pill">{dashboard.gateways.length} Gateways</span>
          <span className="metric-pill">{dashboard.logs.length} Logs</span>
        </div>
      }
      headerActions={
        <button className="secondary-button" disabled={isRefreshing} type="button" onClick={() => void handleRefresh()}>
          {isRefreshing ? 'Refreshing...' : 'Refresh data'}
        </button>
      }
      sidebar={
        <nav className="sidebar-nav" aria-label="App pages">
          <div className="sidebar-nav__intro">
            <p className="eyebrow">Navigation</p>
            <h2>Monitor</h2>
            <p className="muted">Switch between monitoring, topology, and resource configuration views.</p>
          </div>
          <button className="sidebar-link" type="button" aria-current={currentPage === 'monitor' ? 'page' : undefined} onClick={() => setCurrentPage('monitor')}>
            <span>Monitor</span>
            <small>{dashboard.providers.length + dashboard.gateways.length + dashboard.logs.length}</small>
          </button>
          <button className="sidebar-link" type="button" aria-current={currentPage === 'topology' ? 'page' : undefined} onClick={() => setCurrentPage('topology')}>
            <span>Topology</span>
            <small>Map</small>
          </button>
          <button className="sidebar-link" type="button" aria-current={currentPage === 'providers' ? 'page' : undefined} onClick={() => setCurrentPage('providers')}>
            <span>Providers</span>
            <small>{dashboard.providers.length}</small>
          </button>
          <button className="sidebar-link" type="button" aria-current={currentPage === 'gateways' ? 'page' : undefined} onClick={() => setCurrentPage('gateways')}>
            <span>Gateways</span>
            <small>{dashboard.gateways.length}</small>
          </button>
          <button className="sidebar-link" type="button" aria-current={currentPage === 'logs' ? 'page' : undefined} onClick={() => setCurrentPage('logs')}>
            <span>Logs</span>
            <small>{dashboard.logs.length}</small>
          </button>
          <div className="sidebar-note">
            <p className="muted">Admin scope</p>
            <strong>Provider / Gateway / Logs</strong>
          </div>
        </nav>
      }
    >
      {pageContent}
    </AppShell>
  );
}

export default App;
