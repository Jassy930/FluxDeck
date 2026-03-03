import { StrictMode, type ReactNode } from 'react';
import { createRoot } from 'react-dom/client';
import { App } from './App';

type CreateRootFn = (container: Element | DocumentFragment) => {
  render(node: ReactNode): void;
};

export function mountApp(
  doc: Pick<Document, 'getElementById'>,
  createRootFn: CreateRootFn = createRoot,
): void {
  const root = doc.getElementById('root');
  if (!root) {
    throw new Error('Missing #root container');
  }
  createRootFn(root).render(
    <StrictMode>
      <App />
    </StrictMode>,
  );
}

if (typeof document !== 'undefined') {
  mountApp(document);
}
