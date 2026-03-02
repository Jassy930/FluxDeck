import type { AdminApi, CreateGatewayInput, Gateway } from '../api/admin';

export async function submitGatewayForm(api: AdminApi, input: CreateGatewayInput): Promise<Gateway> {
  return api.createGateway(input);
}
