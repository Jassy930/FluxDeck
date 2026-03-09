import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { AlertFeed } from './AlertFeed';

describe('AlertFeed', () => {
  it('renders info, warning, and error alerts with visible status labels', () => {
    const html = renderToStaticMarkup(
      <AlertFeed
        alerts={[
          {
            id: 'alert-1',
            level: 'info',
            title: 'Gateway warmup completed',
            detail: 'gateway_main finished startup checks.',
            timestamp: 'just now',
          },
          {
            id: 'alert-2',
            level: 'warning',
            title: 'Latency increased',
            detail: 'gateway_map P95 climbed above the target band.',
            timestamp: '2m ago',
          },
          {
            id: 'alert-3',
            level: 'error',
            title: 'Provider timeout',
            detail: 'provider_main timed out during upstream failover.',
            timestamp: '5m ago',
          },
        ]}
      />,
    );

    expect(html).toContain('Gateway warmup completed');
    expect(html).toContain('Latency increased');
    expect(html).toContain('Provider timeout');
    expect(html).toContain('Info');
    expect(html).toContain('Warning');
    expect(html).toContain('Error');
    expect(html).toContain('alert-feed__badge alert-feed__badge--error');
  });

  it('renders empty-state guidance when there are no alerts', () => {
    const html = renderToStaticMarkup(<AlertFeed alerts={[]} emptyTitle="No alerts yet." emptyDescription="Recent provider errors, fallback hits, and gateway warnings will surface here." />);

    expect(html).toContain('No alerts yet.');
    expect(html).toContain('Recent provider errors, fallback hits, and gateway warnings will surface here.');
  });
});
