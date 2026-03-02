import type { Provider } from '../api/admin';

export function renderProviderPanel(providers: Provider[]): string {
  const rows = providers.map((item) => `${item.name} (${item.kind})`).join(' | ');
  return `Providers: ${rows || 'empty'}`;
}
