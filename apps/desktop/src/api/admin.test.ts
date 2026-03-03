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
});
