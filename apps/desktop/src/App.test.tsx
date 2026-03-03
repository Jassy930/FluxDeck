import { describe, expect, it } from 'bun:test';
import { mountApp } from './entry';

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
