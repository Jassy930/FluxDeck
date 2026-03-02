import type { RequestLog } from '../api/admin';

export function renderLogPanel(logs: RequestLog[]): string {
  const rows = logs.map((item) => `${item.request_id}:${item.status_code}`).join(' | ');
  return `Logs: ${rows || 'empty'}`;
}
