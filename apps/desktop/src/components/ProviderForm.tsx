import type { AdminApi, CreateProviderInput, Provider } from '../api/admin';

type ProviderFormProps = {
  onSubmit: (input: CreateProviderInput) => Promise<void> | void;
};

export function ProviderForm({ onSubmit }: ProviderFormProps) {
  return (
    <button
      type="button"
      onClick={() =>
        void onSubmit({
          id: 'provider_demo',
          name: 'Demo Provider',
          kind: 'openai',
          base_url: 'https://api.openai.com/v1',
          api_key: 'sk-demo',
          models: ['gpt-4o-mini'],
          enabled: true,
        })
      }
    >
      Create Provider
    </button>
  );
}

export async function submitProviderForm(api: AdminApi, input: CreateProviderInput): Promise<Provider> {
  return api.createProvider(input);
}
