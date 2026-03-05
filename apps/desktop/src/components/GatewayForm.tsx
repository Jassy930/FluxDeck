import type { AdminApi, CreateGatewayInput, Gateway } from '../api/admin';

type GatewayFormProps = {
  onSubmit: (input: CreateGatewayInput) => Promise<void> | void;
};

export function GatewayForm({ onSubmit }: GatewayFormProps) {
  return (
    <button
      type="button"
      onClick={() =>
        void onSubmit({
          id: 'gateway_demo',
          name: 'Demo Gateway',
          listen_host: '127.0.0.1',
          listen_port: 18080,
          inbound_protocol: 'anthropic',
          upstream_protocol: 'openai',
          protocol_config_json: {
            compatibility_mode: 'compatible',
          },
          default_provider_id: 'provider_demo',
          default_model: 'claude-3-7-sonnet',
          enabled: true,
        })
      }
    >
      Create Gateway
    </button>
  );
}

export async function submitGatewayForm(api: AdminApi, input: CreateGatewayInput): Promise<Gateway> {
  return api.createGateway(input);
}
