import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import {
  ProviderForm,
  buildProviderInput,
  type ProviderFormState,
} from './ProviderForm';
import {
  GatewayForm,
  buildGatewayInput,
  type GatewayFormState,
} from './GatewayForm';

describe('provider form', () => {
  it('renders labeled fields for provider settings', () => {
    const html = renderToStaticMarkup(<ProviderForm onSubmit={() => undefined} />);

    expect(html).toContain('Provider ID');
    expect(html).toContain('Provider Name');
    expect(html).toContain('Base URL');
    expect(html).toContain('API Key');
    expect(html).toContain('Models');
    expect(html).toContain('Create Provider');
  });

  it('builds provider input from editable form state', () => {
    const state: ProviderFormState = {
      id: ' provider_main ',
      name: ' Main Provider ',
      kind: 'openai',
      baseUrl: ' https://api.openai.com/v1 ',
      apiKey: ' sk-live ',
      modelsText: 'gpt-4o-mini, gpt-4.1 , ,o3-mini',
      enabled: true,
    };

    expect(buildProviderInput(state)).toEqual({
      id: 'provider_main',
      name: 'Main Provider',
      kind: 'openai',
      base_url: 'https://api.openai.com/v1',
      api_key: 'sk-live',
      models: ['gpt-4o-mini', 'gpt-4.1', 'o3-mini'],
      enabled: true,
    });
  });
});

describe('gateway form', () => {
  it('renders labeled fields for gateway settings', () => {
    const html = renderToStaticMarkup(<GatewayForm onSubmit={() => undefined} />);

    expect(html).toContain('Gateway ID');
    expect(html).toContain('Gateway Name');
    expect(html).toContain('Listen Host');
    expect(html).toContain('Listen Port');
    expect(html).toContain('Default Provider ID');
    expect(html).toContain('Default Model');
    expect(html).toContain('Protocol Config JSON');
    expect(html).toContain('Create Gateway');
  });

  it('builds gateway input from editable form state', () => {
    const state: GatewayFormState = {
      id: ' gateway_main ',
      name: ' Main Gateway ',
      listenHost: ' 127.0.0.1 ',
      listenPort: '18080',
      inboundProtocol: 'anthropic',
      upstreamProtocol: 'openai',
      protocolConfigText: '{"compatibility_mode":"compatible"}',
      defaultProviderId: ' provider_main ',
      defaultModel: ' claude-3-7-sonnet ',
      enabled: true,
    };

    expect(buildGatewayInput(state)).toEqual({
      id: 'gateway_main',
      name: 'Main Gateway',
      listen_host: '127.0.0.1',
      listen_port: 18080,
      inbound_protocol: 'anthropic',
      upstream_protocol: 'openai',
      protocol_config_json: {
        compatibility_mode: 'compatible',
      },
      default_provider_id: 'provider_main',
      default_model: 'claude-3-7-sonnet',
      enabled: true,
    });
  });
});
