import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { mountApp } from './entry';
import { App, createGatewayFromUi, createProviderFromUi, refreshAll } from './App';
import type { AdminApi } from './api/admin';
import { GatewaySection } from './ui/gateways/GatewaySection';

describe('desktop entry', () => {
  it('mounts app root into #root', () => {
    const calls: string[] = [];
    const rootElement = { id: 'root' };
    const fakeDocument = {
      getElementById: (id: string) => {
        calls.push(`getElementById:${id}`);
        return id === 'root' ? (rootElement as unknown as HTMLElement) : null;
      },
    } as Pick<Document, 'getElementById'>;

    const fakeCreateRoot = (container: Element | DocumentFragment) => {
      calls.push(`createRoot:${(container as HTMLElement).id}`);
      return {
        render: () => {
          calls.push('render');
        },
      };
    };

    mountApp(fakeDocument, fakeCreateRoot);

    expect(calls).toEqual(['getElementById:root', 'createRoot:root', 'render']);
  });
});

describe('desktop app shell', () => {
  it('renders monitor-first navigation shell with resource sections', () => {
    const html = renderToStaticMarkup(<App />);

    expect(html).toContain('FluxDeck Admin');
    expect(html).toContain('Skip to main content');
    expect(html).toContain('Monitor');
    expect(html).toContain('Topology');
    expect(html).toContain('Providers');
    expect(html).toContain('Gateways');
    expect(html).toContain('Logs');
    expect(html).toContain('Refresh data');
    expect(html).toContain('Monitor overview');
    expect(html).toContain('window-toolbar');
    expect(html).toContain('window-sidebar');
    expect(html).not.toContain('Topology workspace');
  });
});

describe('monitor page', () => {
  it('renders monitor dashboard scaffolding with key health sections', () => {
    const html = renderToStaticMarkup(<App />);

    expect(html).toContain('Running Gateways');
    expect(html).toContain('Active Providers');
    expect(html).toContain('Requests / min');
    expect(html).toContain('P95 Latency');
    expect(html).toContain('Recent Alerts');
    expect(html).toContain('Gateway Runtime Board');
  });
});

describe('topology page', () => {
  it('renders topology workspace when initial page is topology', () => {
    const html = renderToStaticMarkup(<App initialPage="topology" />);

    expect(html).toContain('Live Flow');
    expect(html).toContain('Failure Path');
    expect(html).toContain('Gateways');
    expect(html).toContain('Providers');
    expect(html).toContain('Models');
  });
});

describe('provider section', () => {
  it('creates provider from ui and refreshes all dashboard lists', async () => {
    const calls: string[] = [];
    const api: AdminApi = {
      listProviders: async () => {
        calls.push('listProviders');
        return { items: [], next_cursor: null, has_more: false };
      },
      listGateways: async () => {
        calls.push('listGateways');
        return { items: [], next_cursor: null, has_more: false };
      },
      listLogs: async () => {
        calls.push('listLogs');
        return { items: [], next_cursor: null, has_more: false };
      },
      createProvider: async (input) => {
        calls.push(`createProvider:${input.id}`);
        return {
          id: input.id,
          name: input.name,
          kind: input.kind,
          base_url: input.base_url,
          enabled: input.enabled,
        };
      },
      createGateway: async (input) => {
        calls.push(`createGateway:${input.id}:${input.upstream_protocol}`);
        return {
          id: input.id,
          name: input.name,
          listen_host: input.listen_host,
          listen_port: input.listen_port,
          inbound_protocol: input.inbound_protocol,
          upstream_protocol: input.upstream_protocol,
          protocol_config_json: input.protocol_config_json,
          default_provider_id: input.default_provider_id,
          enabled: input.enabled,
        };
      },
    };

    await createProviderFromUi(api, {
      id: 'provider_ui_1',
      name: 'UI Provider',
      kind: 'openai',
      base_url: 'https://api.openai.com/v1',
      api_key: 'sk-ui',
      models: ['gpt-4o-mini'],
      enabled: true,
    });

    expect(calls).toEqual([
      'createProvider:provider_ui_1',
      'listProviders',
      'listGateways',
      'listLogs',
    ]);
  });
});

describe('dashboard refresh pagination', () => {
  it('unwraps paginated logs items into dashboard state', async () => {
    const api: AdminApi = {
      listProviders: async () => [],
      listGateways: async () => [],
      listLogs: async () => ({
        items: [
          {
            request_id: 'req_001',
            gateway_id: 'gateway_main',
            provider_id: 'provider_main',
            model: 'gpt-4o-mini',
            status_code: 200,
            latency_ms: 120,
            error: null,
            created_at: '2026-03-08T10:00:00Z',
          },
        ],
        next_cursor: null,
        has_more: false,
      }),
      createProvider: async () => {
        throw new Error('not used');
      },
      createGateway: async () => {
        throw new Error('not used');
      },
    };

    const dashboard = await refreshAll(api);

    expect(dashboard.logs).toEqual([
      {
        request_id: 'req_001',
        gateway_id: 'gateway_main',
        provider_id: 'provider_main',
        model: 'gpt-4o-mini',
        status_code: 200,
        latency_ms: 120,
        error: null,
        created_at: '2026-03-08T10:00:00Z',
      },
    ]);
  });
});

describe('dashboard refresh', () => {
  it('loads providers gateways logs in one refresh action', async () => {
    const calls: string[] = [];
    const api: AdminApi = {
      listProviders: async () => {
        calls.push('listProviders');
        return { items: [], next_cursor: null, has_more: false };
      },
      listGateways: async () => {
        calls.push('listGateways');
        return [];
      },
      listLogs: async () => {
        calls.push('listLogs');
        return [];
      },
      createProvider: async () => {
        throw new Error('not used');
      },
      createGateway: async () => {
        throw new Error('not used');
      },
    };

    await refreshAll(api);

    expect(calls.sort()).toEqual(['listGateways', 'listLogs', 'listProviders']);
  });
});

describe('gateway section', () => {
  it('shows gateway runtime status and last error in ui', () => {
    const html = renderToStaticMarkup(
      <GatewaySection
        gateways={[
          {
            id: 'gateway_main',
            name: 'Gateway Main',
            listen_host: '127.0.0.1',
            listen_port: 18080,
            inbound_protocol: 'openai',
            upstream_protocol: 'provider_default',
            protocol_config_json: {},
            default_provider_id: 'provider_main',
            enabled: true,
            runtime_status: 'error',
            last_error: 'upstream timeout',
          },
        ]}
      />,
    );

    expect(html).toContain('Runtime: error');
    expect(html).toContain('Last error: upstream timeout');
  });

  it('creates gateway from ui and refreshes all dashboard lists', async () => {
    const calls: string[] = [];
    const api: AdminApi = {
      listProviders: async () => {
        calls.push('listProviders');
        return [];
      },
      listGateways: async () => {
        calls.push('listGateways');
        return [];
      },
      listLogs: async () => {
        calls.push('listLogs');
        return [];
      },
      createProvider: async () => {
        throw new Error('not used');
      },
      createGateway: async (input) => {
        calls.push(`createGateway:${input.id}:${input.upstream_protocol}`);
        return {
          id: input.id,
          name: input.name,
          listen_host: input.listen_host,
          listen_port: input.listen_port,
          inbound_protocol: input.inbound_protocol,
          upstream_protocol: input.upstream_protocol,
          protocol_config_json: input.protocol_config_json,
          default_provider_id: input.default_provider_id,
          enabled: input.enabled,
        };
      },
    };

    await createGatewayFromUi(api, {
      id: 'gateway_ui_1',
      name: 'UI Gateway',
      listen_host: '127.0.0.1',
      listen_port: 18080,
      inbound_protocol: 'anthropic',
      upstream_protocol: 'openai',
      protocol_config_json: { compatibility_mode: 'compatible' },
      default_provider_id: 'provider_ui_1',
      default_model: 'claude-3-7-sonnet',
      enabled: true,
    });

    expect(calls).toEqual([
      'createGateway:gateway_ui_1:openai',
      'listProviders',
      'listGateways',
      'listLogs',
    ]);
  });
});
