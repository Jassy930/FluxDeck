import { useState } from 'react';
import type { AdminApi, CreateProviderInput, Provider } from '../api/admin';

export type ProviderFormState = {
  id: string;
  name: string;
  kind: string;
  baseUrl: string;
  apiKey: string;
  modelsText: string;
  enabled: boolean;
};

type ProviderFormProps = {
  onSubmit: (input: CreateProviderInput) => Promise<void> | void;
};

const DEFAULT_PROVIDER_FORM_STATE: ProviderFormState = {
  id: 'provider_demo',
  name: 'Demo Provider',
  kind: 'openai',
  baseUrl: 'https://api.openai.com/v1',
  apiKey: 'sk-demo',
  modelsText: 'gpt-4o-mini',
  enabled: true,
};

export function buildProviderInput(state: ProviderFormState): CreateProviderInput {
  return {
    id: state.id.trim(),
    name: state.name.trim(),
    kind: state.kind.trim(),
    base_url: state.baseUrl.trim(),
    api_key: state.apiKey.trim(),
    models: state.modelsText
      .split(/[\n,]/)
      .map((item) => item.trim())
      .filter(Boolean),
    enabled: state.enabled,
  };
}

export function ProviderForm({ onSubmit }: ProviderFormProps) {
  const [formState, setFormState] = useState<ProviderFormState>(DEFAULT_PROVIDER_FORM_STATE);
  const [isSubmitting, setIsSubmitting] = useState(false);
  const [submitError, setSubmitError] = useState<string | null>(null);

  async function handleSubmit(event: React.FormEvent<HTMLFormElement>) {
    event.preventDefault();
    setIsSubmitting(true);
    setSubmitError(null);

    try {
      await onSubmit(buildProviderInput(formState));
    } catch (error: unknown) {
      setSubmitError(error instanceof Error ? error.message : 'Failed to create provider');
    } finally {
      setIsSubmitting(false);
    }
  }

  function updateField<Key extends keyof ProviderFormState>(key: Key, value: ProviderFormState[Key]) {
    setFormState((current) => ({ ...current, [key]: value }));
  }

  return (
    <form className="settings-form" onSubmit={handleSubmit}>
      <div className="section-heading section-heading--compact">
        <div>
          <p className="eyebrow">Quick create</p>
          <h3>Create provider</h3>
          <p className="muted">Configure an upstream OpenAI-compatible provider for local routing.</p>
        </div>
      </div>
      <div className="form-grid">
        <label className="field">
          <span>Provider ID</span>
          <input
            className="text-input"
            name="provider-id"
            value={formState.id}
            onChange={(event) => updateField('id', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Provider Name</span>
          <input
            className="text-input"
            name="provider-name"
            value={formState.name}
            onChange={(event) => updateField('name', event.target.value)}
          />
        </label>
        <label className="field">
          <span>Kind</span>
          <select
            className="text-input"
            name="provider-kind"
            value={formState.kind}
            onChange={(event) => updateField('kind', event.target.value)}
          >
            <option value="openai">openai</option>
          </select>
        </label>
        <label className="field field--span-2">
          <span>Base URL</span>
          <input
            className="text-input"
            name="provider-base-url"
            value={formState.baseUrl}
            onChange={(event) => updateField('baseUrl', event.target.value)}
          />
        </label>
        <label className="field field--span-2">
          <span>API Key</span>
          <input
            className="text-input"
            name="provider-api-key"
            type="password"
            value={formState.apiKey}
            onChange={(event) => updateField('apiKey', event.target.value)}
          />
        </label>
        <label className="field field--span-2">
          <span>Models</span>
          <textarea
            className="text-input text-input--multiline"
            name="provider-models"
            rows={3}
            value={formState.modelsText}
            onChange={(event) => updateField('modelsText', event.target.value)}
          />
        </label>
      </div>
      <label className="checkbox-row">
        <input
          checked={formState.enabled}
          name="provider-enabled"
          type="checkbox"
          onChange={(event) => updateField('enabled', event.target.checked)}
        />
        <span>Enabled</span>
      </label>
      {submitError ? <p className="form-message form-message--error">{submitError}</p> : null}
      <div className="form-actions">
        <button className="primary-button" disabled={isSubmitting} type="submit">
          {isSubmitting ? 'Creating provider...' : 'Create Provider'}
        </button>
      </div>
    </form>
  );
}

export async function submitProviderForm(api: AdminApi, input: CreateProviderInput): Promise<Provider> {
  return api.createProvider(input);
}
