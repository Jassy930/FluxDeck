import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { TopologyCanvas } from './TopologyCanvas';

describe('TopologyCanvas', () => {
  it('renders four routing layers, a path, and a detail panel shell', () => {
    const html = renderToStaticMarkup(<TopologyCanvas />);

    expect(html).toContain('Entrypoints');
    expect(html).toContain('Gateways');
    expect(html).toContain('Providers');
    expect(html).toContain('Models');
    expect(html).toContain('Selected Route');
    expect(html).toContain('<svg');
  });
});
