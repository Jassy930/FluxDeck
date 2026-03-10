import { afterEach, describe, expect, it } from 'bun:test';
import { createAdminApi } from './admin';

const originalFetch = globalThis.fetch;

afterEach(() => {
  globalThis.fetch = originalFetch;
});

describe('createAdminApi', () => {
  it('uses relative /admin path by default for browser dev proxy', async () => {
    const calls: string[] = [];
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      calls.push(String(input));
      return new Response(JSON.stringify([]), { status: 200 });
    }) as typeof fetch;

    const api = createAdminApi();
    await api.listProviders();

    expect(calls).toEqual(['/admin/providers']);
  });

  it('uses explicit base url when provided', async () => {
    const calls: string[] = [];
    globalThis.fetch = (async (input: RequestInfo | URL) => {
      calls.push(String(input));
      return new Response(JSON.stringify([]), { status: 200 });
    }) as typeof fetch;

    const api = createAdminApi('http://127.0.0.1:7777');
    await api.listProviders();

    expect(calls).toEqual(['http://127.0.0.1:7777/admin/providers']);
  });

  it('posts gateway protocol graph fields', async () => {
    const bodies: string[] = [];
    globalThis.fetch = (async (_input: RequestInfo | URL, init?: RequestInit) => {
      bodies.push((init?.body as string) ?? '');
      return new Response(
        JSON.stringify({
          id: 'gateway_protocol',
          name: 'Protocol Gateway',
          listen_host: '127.0.0.1',
          listen_port: 18080,
          inbound_protocol: 'anthropic',
          upstream_protocol: 'openai',
          protocol_config_json: { compatibility_mode: 'compatible' },
          default_provider_id: 'provider_protocol',
          enabled: true,
        }),
        { status: 200 },
      );
    }) as typeof fetch;

    const api = createAdminApi();
    await api.createGateway({
      id: 'gateway_protocol',
      name: 'Protocol Gateway',
      listen_host: '127.0.0.1',
      listen_port: 18080,
      inbound_protocol: 'anthropic',
      upstream_protocol: 'openai',
      protocol_config_json: { compatibility_mode: 'compatible' },
      default_provider_id: 'provider_protocol',
      default_model: 'claude-3-7-sonnet',
      enabled: true,
      auto_start: false,
    });

    expect(JSON.parse(bodies[0] ?? '{}')).toMatchObject({
      inbound_protocol: 'anthropic',
      upstream_protocol: 'openai',
      protocol_config_json: { compatibility_mode: 'compatible' },
    });
  });
});
