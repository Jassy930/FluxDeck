import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { MetricCard } from './MetricCard';

describe('MetricCard', () => {
  it('renders label value helper and trend copy', () => {
    const html = renderToStaticMarkup(
      <MetricCard
        label="Running Gateways"
        value="3"
        helper="Gateways currently serving traffic"
        trend="+2 in the last hour"
        tone="healthy"
      />,
    );

    expect(html).toContain('Running Gateways');
    expect(html).toContain('3');
    expect(html).toContain('Gateways currently serving traffic');
    expect(html).toContain('+2 in the last hour');
  });

  it('applies semantic tone class names', () => {
    const html = renderToStaticMarkup(
      <>
        <MetricCard label="Healthy" value="1" tone="healthy" />
        <MetricCard label="Warning" value="2" tone="warning" />
        <MetricCard label="Error" value="3" tone="error" />
      </>,
    );

    expect(html).toContain('metric-card metric-card--healthy');
    expect(html).toContain('metric-card metric-card--warning');
    expect(html).toContain('metric-card metric-card--error');
  });
});
