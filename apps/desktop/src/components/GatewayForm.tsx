import { useState } from 'react';
import type { AdminApi, CreateGatewayInput, Gateway } from '../api/admin';

export type GatewayFormState = {
  id: string;
  name: string;
  listenHost: string;
  listenPort: string;
  inboundProtocol: string;
  upstreamProtocol: string;
  protocolConfigText: string;
  defaultProviderId: string;
  defaultModel: string;
  enabled: boolean;
};

type GatewayFormProps = {
  onSubmit: (input: CreateGatewayInput) => Promise<void> | void;
};

const DEFAULT_GATEWAY_FORM_STATE: GatewayFormState = {
  id: 'gateway_demo',
  name: 'Demo Gateway',
  listenHost: '127.0.0.1',
  listenPort: '18080',
  inboundProtocol: 'anthropic',
  upstreamProtocol: 'openai',
  protocolConfigText: JSON.stringify({ compatibility_mode: 'compatible' }, null, 2),
  defaultProviderId: 'provider_demo',
  defaultModel: 'claude-3-7-sonnet',
  enabled: true,
};

export function buildGatewayInput(state: GatewayFormState): CreateGatewayInput {
  return {
    id: state.id.trim(),
    name: state.name.trim(),
    listen_host: state.listenHost.trim(),
    listen_port: Number.parseInt(state.listenPort.trim(), 10),
    inbound_protocol: state.inboundProtocol.trim(),
    upstream_protocol: state.upstreamProtocol.trim(),
    protocol_config_json: JSON.parse(state.protocolConfigText) as Record<string, unknown>,
    default_provider_id: state.defaultProviderId.trim(),
    default_model: state.defaultModel.trim(),
    enabled: state.enabled,
  };
}

export function GatewayForm({ onSubmit }: GatewayFormProps) {
  const [formState, setFormState] = useState<GatewayFormState>(DEFAULT_GATEWAY_FORM_STATE);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSubmitting(true);
    setSubmitError(null);

    try {
      await onSubmit(buildGatewayInput(formState));
    } catch (error: unknown) {
      setSubmitError(error instanceof Error ? error.message : 'Failed to create gateway');
    } finally {
      setIsSubmitting(false);
    }
  }

  function updateField<Key extends keyof GatewayFormState>(key: Key, value: GatewayFormState[Key]) {
    setFormState((current) => ({ ...current, [key]: value }));
  }

  return (
    <form className="settings-form" onSubmit={handleSubmit}>
      <div className="section-heading section-heading--compact">
        <div>
          <p className="eyebrow">Quick create</p>
          <h3>Create gateway</h3>
          <p className="muted">Expose a local compatible endpoint and map it to your default provider.</p>
        </div>
      </div>
      <div className="form-grid">
        <label className="field">
          <span>Gateway ID</span>
          <input
            className="text-input"
            name="gateway-id"
            value={formState.id}
            onChange={(event) => updateField('id', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Gateway Name</span>
          <input
            className="text-input"
            name="gateway-name"
            value={formState.name}
            onChange={(event) => updateField('name', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Listen Host</span>
          <input
            className="text-input"
            name="listen-host"
            value={formState.listenHost}
            onChange={(event) => updateField('listenHost', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Listen Port</span>
          <input
            className="text-input"
            name="listen-port"
            inputMode="numeric"
            value={formState.listenPort}
            onChange={(event) => updateField('listenPort', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Inbound Protocol</span>
          <select
            className="text-input"
            name="inbound-protocol"
            value={formState.inboundProtocol}
            onChange={(event) => updateField('inboundProtocol', event.target.value)}
          >
            <option value="openai">openai</option>
            <option value="anthropic">anthropic</option>
          </select>
        </label>
        <label className="field">
          <span>Upstream Protocol</span>
          <select
            className="text-input"
            name="upstream-protocol"
            value={formState.upstreamProtocol}
            onChange={(event) => updateField('upstreamProtocol', event.target.value)}
          >
            <option value="openai">openai</option>
            <option value="provider_default">provider_default</option>
          </select>
        </label>
        <label className="field">
          <span>Default Provider ID</span>
          <input
            className="text-input"
            name="default-provider-id"
            value={formState.defaultProviderId}
            onChange={(event) => updateField('defaultProviderId', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Default Model</span>
          <input
            className="text-input"
            name="default-model"
            value={formState.defaultModel}
            onChange={(event) => updateField('defaultModel', event.target.value)}
          />
        </label>
        <label className="field field--span-2">
          <span>Protocol Config JSON</span>
          <textarea
            className="text-input text-input--multiline"
            name="protocol-config-json"
            rows={4}
            value={formState.protocolConfigText}
            onChange={(event) => updateField('protocolConfigText', event.target.value)}
          />
        </label>
      </div>
      <label className="checkbox-row">
        <input
          checked={formState.enabled}
          name="gateway-enabled"
          type="checkbox"
          onChange={(event) => updateField('enabled', event.target.checked)}
        />
        <span>Enabled</span>
      </label>
      {submitError ? <p className="form-message form-message--error">{submitError}</p> : null}
      <div className="form-actions">
        <button className="primary-button" disabled={isSubmitting} type="submit">
          {isSubmitting ? 'Creating gateway...' : 'Create Gateway'}
        </button>
      </div>
    </form>
  );
}

export async function submitGatewayForm(api: AdminApi, input: CreateGatewayInput): Promise<Gateway> {
  return api.createGateway(input);
}
