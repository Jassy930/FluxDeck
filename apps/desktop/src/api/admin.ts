export type Provider = {
  id: string;
  name: string;
  kind: string;
  base_url: string;
  api_key: string;
  models: string[];
  enabled: boolean;
};

export type Gateway = {
  id: string;
  name: string;
  listen_host: string;
  listen_port: number;
  inbound_protocol: string;
  upstream_protocol: string;
  protocol_config_json: Record<string, unknown>;
  default_provider_id: string;
  default_model: string | null;
  enabled: boolean;
  auto_start: boolean;
  runtime_status: 'running' | 'stopped' | string;
  last_error: string | null;
};

export type RequestLog = {
  request_id: string;
  gateway_id: string;
  provider_id: string;
  model: string | null;
  inbound_protocol: string | null;
  upstream_protocol: string | null;
  model_requested: string | null;
  model_effective: string | null;
  status_code: number;
  latency_ms: number;
  stream: boolean;
  first_byte_ms: number | null;
  input_tokens: number | null;
  output_tokens: number | null;
  total_tokens: number | null;
  usage_json: string | null;
  error_stage: string | null;
  error_type: string | null;
  error: string | null;
  created_at: string;
};

export type RequestLogCursor = {
  created_at: string;
  request_id: string;
};

export type RequestLogPage = {
  items: RequestLog[];
  next_cursor: RequestLogCursor | null;
  has_more: boolean;
};

export type ListLogsParams = {
  limit?: number;
  cursor_created_at?: string;
  cursor_request_id?: string;
  gateway_id?: string;
  provider_id?: string;
  status_code?: number;
  errors_only?: boolean;
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
  upstream_protocol: string;
  protocol_config_json: Record<string, unknown>;
  default_provider_id: string;
  default_model: string | null;
  enabled: boolean;
  auto_start: boolean;
};

export type AdminApi = {
  listProviders: () => Promise<Provider[]>;
  listGateways: () => Promise<Gateway[]>;
  listLogs: (params?: ListLogsParams) => Promise<RequestLogPage>;
  createProvider: (input: CreateProviderInput) => Promise<Provider>;
  createGateway: (input: CreateGatewayInput) => Promise<Gateway>;
  getStatsOverview: (period?: string) => Promise<StatsOverview>;
  getStatsTrend: (period?: string, interval?: string) => Promise<StatsTrend>;
};

// Stats types
export type StatsOverview = {
  total_requests: number;
  successful_requests: number;
  error_requests: number;
  success_rate: number;
  requests_per_minute: number;
  total_tokens: number;
  by_gateway: GatewayStats[];
  by_provider: ProviderStats[];
  by_model: ModelStats[];
};

export type GatewayStats = {
  gateway_id: string;
  request_count: number;
  success_count: number;
  error_count: number;
  total_tokens: number;
  avg_latency: number;
};

export type ProviderStats = {
  provider_id: string;
  request_count: number;
  success_count: number;
  error_count: number;
  total_tokens: number;
  avg_latency: number;
};

export type ModelStats = {
  model: string;
  request_count: number;
  success_count: number;
  error_count: number;
  total_tokens: number;
  avg_latency: number;
};

export type StatsTrendPoint = {
  timestamp: string;
  request_count: number;
  avg_latency: number;
  error_count: number;
  input_tokens: number;
  output_tokens: number;
};

export type StatsTrend = {
  period: string;
  interval: string;
  data: StatsTrendPoint[];
}

export type DashboardLists = {
  providers: Provider[];
  gateways: Gateway[];
  logs: RequestLog[];
};

export async function listDashboardLists(
  api: Pick<AdminApi, 'listProviders' | 'listGateways' | 'listLogs'>,
): Promise<DashboardLists> {
  const [providers, gateways, logsPage] = await Promise.all([
    api.listProviders(),
    api.listGateways(),
    api.listLogs({ limit: 20 }),
  ]);
  return { providers, gateways, logs: logsPage.items };
}

export function createAdminApi(baseUrl = ''): AdminApi {
  const normalized = baseUrl.replace(/\/$/, '');
  const buildUrl = (path: string) => (normalized ? `${normalized}${path}` : path);

  async function getJson<T>(path: string, params?: URLSearchParams): Promise<T> {
    const target = params && Array.from(params.keys()).length > 0 ? `${buildUrl(path)}?${params.toString()}` : buildUrl(path);
    const response = await fetch(target);
    if (!response.ok) {
      throw new Error(`admin api failed: ${response.status}`);
    }
    return (await response.json()) as T;
  }

  async function postJson<TReq, TResp>(path: string, body: TReq): Promise<TResp> {
    const response = await fetch(buildUrl(path), {
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
    listLogs: (params) => {
      const query = new URLSearchParams();
      if (params?.limit !== undefined) query.set('limit', String(params.limit));
      if (params?.cursor_created_at) query.set('cursor_created_at', params.cursor_created_at);
      if (params?.cursor_request_id) query.set('cursor_request_id', params.cursor_request_id);
      if (params?.gateway_id) query.set('gateway_id', params.gateway_id);
      if (params?.provider_id) query.set('provider_id', params.provider_id);
      if (params?.status_code !== undefined) query.set('status_code', String(params.status_code));
      if (params?.errors_only) query.set('errors_only', 'true');
      return getJson<RequestLogPage>('/admin/logs', query);
    },
    createProvider: (input) => postJson<CreateProviderInput, Provider>('/admin/providers', input),
    createGateway: (input) => postJson<CreateGatewayInput, Gateway>('/admin/gateways', input),
    getStatsOverview: (period = '1h') => {
      const query = new URLSearchParams({ period });
      return getJson<StatsOverview>('/admin/stats/overview', query);
    },
    getStatsTrend: (period = '1h', interval = '5m') => {
      const query = new URLSearchParams({ period, interval });
      return getJson<StatsTrend>('/admin/stats/trend', query);
    },
  };
}
