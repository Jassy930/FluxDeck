import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { TrendPanel } from './TrendPanel';

describe('TrendPanel', () => {
  it('renders trend headings, time filters, and svg chart primitives', () => {
    const html = renderToStaticMarkup(<TrendPanel />);

    expect(html).toContain('Request Throughput');
    expect(html).toContain('Latency Trend');
    expect(html).toContain('1m');
    expect(html).toContain('5m');
    expect(html).toContain('15m');
    expect(html).toContain('1h');
    expect(html).toContain('<svg');
  });
});
