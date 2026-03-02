import { createAdminApi, type AdminApi, type Gateway, type Provider, type RequestLog } from './api/admin';
import { renderGatewayPanel } from './components/GatewayPanel';
import { renderLogPanel } from './components/LogPanel';
import { renderProviderPanel } from './components/ProviderPanel';

export type DashboardData = {
  providers: Provider[];
  gateways: Gateway[];
  logs: RequestLog[];
};

export function appSections(): string[] {
  return ['Providers', 'Gateways', 'Logs'];
}

export async function loadDashboard(api: AdminApi = createAdminApi()): Promise<DashboardData> {
  const [providers, gateways, logs] = await Promise.all([
    api.listProviders(),
    api.listGateways(),
    api.listLogs(),
  ]);

  return { providers, gateways, logs };
}

export async function renderDashboardText(api?: AdminApi): Promise<string[]> {
  const data = await loadDashboard(api);
  return [
    renderProviderPanel(data.providers),
    renderGatewayPanel(data.gateways),
    renderLogPanel(data.logs),
  ];
}
