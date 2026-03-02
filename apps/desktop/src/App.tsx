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
  const runtimeLine = renderGatewayRuntimeLine(data.gateways);
  return [
    renderProviderPanel(data.providers),
    runtimeLine ? `${renderGatewayPanel(data.gateways)} | ${runtimeLine}` : renderGatewayPanel(data.gateways),
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

type GatewayRuntimeView = Gateway & {
  runtime_status?: string;
  last_error?: string | null;
};

function renderGatewayRuntimeLine(gateways: Gateway[]): string {
  const lines = (gateways as GatewayRuntimeView[])
    .map((item) => {
      const status = item.runtime_status ?? 'unknown';
      const error = item.last_error ? `,error=${item.last_error}` : '';
      return `${item.id}:${status}${error}`;
    })
    .join(' | ');
  return lines ? `Runtime: ${lines}` : '';
}
