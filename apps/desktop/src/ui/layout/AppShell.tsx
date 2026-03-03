import type { ReactNode } from 'react';

type AppShellProps = {
  title: string;
  sidebar: ReactNode;
  children: ReactNode;
};

export function AppShell({ title, sidebar, children }: AppShellProps) {
  return (
    <div className="app-shell">
      <header className="app-shell__header">
        <strong>{title}</strong>
        <span className="muted">Desktop Runnable UI</span>
      </header>
      <aside className="app-shell__sidebar">{sidebar}</aside>
      <main className="app-shell__main">{children}</main>
    </div>
  );
}
