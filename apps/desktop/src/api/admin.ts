export type Provider = {
  id: string;
  name: string;
  kind: string;
  base_url: string;
  api_key?: string;
  models?: string[];
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

export type CreateProviderInput = {
  id: string;
  name: string;
  kind: string;
  base_url: string;
  api_key: string;
  models: string[];
  enabled: boolean;
};

export type CreateGatewayInput = {
  id: string;
  name: string;
  listen_host: string;
  listen_port: number;
  inbound_protocol: string;
  default_provider_id: string;
  default_model: string;
  enabled: boolean;
};

export type AdminApi = {
  listProviders: () => Promise<Provider[]>;
  listGateways: () => Promise<Gateway[]>;
  listLogs: () => Promise<RequestLog[]>;
  createProvider: (input: CreateProviderInput) => Promise<Provider>;
  createGateway: (input: CreateGatewayInput) => Promise<Gateway>;
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

  async function postJson<TReq, TResp>(path: string, body: TReq): Promise<TResp> {
    const response = await fetch(`${normalized}${path}`, {
      method: 'POST',
      headers: { 'content-type': 'application/json' },
      body: JSON.stringify(body),
    });

    if (!response.ok) {
      throw new Error(`admin api failed: ${response.status}`);
    }
    return (await response.json()) as TResp;
  }

  return {
    listProviders: () => getJson<Provider[]>('/admin/providers'),
    listGateways: () => getJson<Gateway[]>('/admin/gateways'),
    listLogs: () => getJson<RequestLog[]>('/admin/logs'),
    createProvider: (input) => postJson<CreateProviderInput, Provider>('/admin/providers', input),
    createGateway: (input) => postJson<CreateGatewayInput, Gateway>('/admin/gateways', input),
  };
}
