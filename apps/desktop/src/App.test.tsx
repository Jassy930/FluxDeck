import { describe, expect, it } from 'bun:test';
import { renderToStaticMarkup } from 'react-dom/server';
import { mountApp } from './entry';
import { App } from './App';

describe('desktop entry', () => {
  it('mounts app root into #root', () => {
    const calls: string[] = [];
    const rootElement = { id: 'root' };
    const fakeDocument = {
      getElementById: (id: string) => {
        calls.push(`getElementById:${id}`);
        return id === 'root' ? (rootElement as unknown as HTMLElement) : null;
      },
    } as Pick<Document, 'getElementById'>;

    const fakeCreateRoot = (container: Element | DocumentFragment) => {
      calls.push(`createRoot:${(container as HTMLElement).id}`);
      return {
        render: () => {
          calls.push('render');
        },
      };
    };

    mountApp(fakeDocument, fakeCreateRoot);

    expect(calls).toEqual(['getElementById:root', 'createRoot:root', 'render']);
  });
});

describe('desktop app shell', () => {
  it('renders app shell with header sidebar and content sections', () => {
    const html = renderToStaticMarkup(<App />);

    expect(html).toContain('FluxDeck Admin');
    expect(html).toContain('Sidebar');
    expect(html).toContain('Providers');
    expect(html).toContain('Gateways');
    expect(html).toContain('Logs');
  });
});
