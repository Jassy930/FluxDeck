import type { AdminApi, CreateProviderInput, Provider } from '../api/admin';

export async function submitProviderForm(api: AdminApi, input: CreateProviderInput): Promise<Provider> {
  return api.createProvider(input);
}
