import {
  createAdminApi,
  type AdminApi,
  type CreateGatewayInput,
  type CreateProviderInput,
  type Gateway,
  type Provider,
  type RequestLog,
} from './api/admin';
import { submitGatewayForm } from './components/GatewayForm';
import { renderGatewayPanel } from './components/GatewayPanel';
import { renderLogPanel } from './components/LogPanel';
import { submitProviderForm } from './components/ProviderForm';
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

export async function createProviderAndGatewayFromUi(
  api: AdminApi,
  providerInput: CreateProviderInput,
  gatewayInput: CreateGatewayInput,
): Promise<DashboardData> {
  await submitProviderForm(api, providerInput);
  await submitGatewayForm(api, gatewayInput);
  return loadDashboard(api);
}
