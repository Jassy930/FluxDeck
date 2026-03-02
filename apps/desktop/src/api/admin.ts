export type Provider = {
  id: string;
  name: string;
  kind: string;
  base_url: string;
  enabled: boolean;
};

export type Gateway = {
  id: string;
  name: string;
  listen_host: string;
  listen_port: number;
  inbound_protocol: string;
  default_provider_id: string;
  enabled: boolean;
};

export type RequestLog = {
  request_id: string;
  gateway_id: string;
  provider_id: string;
  model: string | null;
  status_code: number;
  latency_ms: number;
  error: string | null;
  created_at: string;
};

export type AdminApi = {
  listProviders: () => Promise<Provider[]>;
  listGateways: () => Promise<Gateway[]>;
  listLogs: () => Promise<RequestLog[]>;
};

export function createAdminApi(baseUrl = 'http://127.0.0.1:7777'): AdminApi {
  const normalized = baseUrl.replace(/\/$/, '');

  async function getJson<T>(path: string): Promise<T> {
    const response = await fetch(`${normalized}${path}`);
    if (!response.ok) {
      throw new Error(`admin api failed: ${response.status}`);
    }
    return (await response.json()) as T;
  }

  return {
    listProviders: () => getJson<Provider[]>('/admin/providers'),
    listGateways: () => getJson<Gateway[]>('/admin/gateways'),
    listLogs: () => getJson<RequestLog[]>('/admin/logs'),
  };
}
