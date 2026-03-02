import type { Gateway } from '../api/admin';

export function renderGatewayPanel(gateways: Gateway[]): string {
  const rows = gateways
    .map((item) => `${item.name}@${item.listen_host}:${item.listen_port}`)
    .join(' | ');
  return `Gateways: ${rows || 'empty'}`;
}
