import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { mountApp } from './entry';
import { App, createProviderFromUi, refreshAll } from './App';
import type { AdminApi } from './api/admin';

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
  it('renders app shell with header sidebar and content sections', () => {
    const html = renderToStaticMarkup(<App />);

    expect(html).toContain('FluxDeck Admin');
    expect(html).toContain('Sidebar');
    expect(html).toContain('Providers');
    expect(html).toContain('Gateways');
    expect(html).toContain('Logs');
  });
});

describe('provider section', () => {
  it('creates provider from ui and refreshes provider list', async () => {
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
        calls.push(`createGateway:${input.id}`);
        return {
          id: input.id,
          name: input.name,
          listen_host: input.listen_host,
          listen_port: input.listen_port,
          inbound_protocol: input.inbound_protocol,
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

    expect(calls).toEqual(['createProvider:provider_ui_1', 'listProviders']);
  });
});

describe('dashboard refresh', () => {
  it('loads providers gateways logs in one refresh action', async () => {
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
      createGateway: async () => {
        throw new Error('not used');
      },
    };

    await refreshAll(api);

    expect(calls.sort()).toEqual(['listGateways', 'listLogs', 'listProviders']);
  });
});
