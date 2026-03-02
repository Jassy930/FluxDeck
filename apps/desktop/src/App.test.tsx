import { describe, expect, it } from 'bun:test';
import { appSections, createProviderAndGatewayFromUi } from './App';
import type { AdminApi } from './api/admin';

describe('desktop app shell', () => {
  it('renders core management panels', () => {
    const sections = appSections();
    expect(sections).toContain('Providers');
    expect(sections).toContain('Gateways');
    expect(sections).toContain('Logs');
  });

  it('can create provider and gateway from ui actions', async () => {
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

    await createProviderAndGatewayFromUi(
      api,
      {
        id: 'provider_ui_1',
        name: 'UI Provider',
        kind: 'openai',
        base_url: 'https://api.openai.com/v1',
        api_key: 'sk-ui',
        models: ['gpt-4o-mini'],
        enabled: true,
      },
      {
        id: 'gateway_ui_1',
        name: 'UI Gateway',
        listen_host: '127.0.0.1',
        listen_port: 18080,
        inbound_protocol: 'openai',
        default_provider_id: 'provider_ui_1',
        default_model: 'gpt-4o-mini',
        enabled: true,
      },
    );

    expect(calls).toEqual([
      'createProvider:provider_ui_1',
      'createGateway:gateway_ui_1',
      'listProviders',
      'listGateways',
      'listLogs',
    ]);
  });
});
