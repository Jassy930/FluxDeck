import type { ReactNode } from 'react';

type AppShellProps = {
  title: string;
  subtitle: string;
  sidebar: ReactNode;
  headerMeta?: ReactNode;
  headerActions?: ReactNode;
  children: ReactNode;
};

export function AppShell({ title, subtitle, sidebar, headerMeta, headerActions, children }: AppShellProps) {
  return (
    <div className="app-shell window-shell">
      <a className="skip-link" href="#main-content">
        Skip to main content
      </a>
      <header className="app-shell__header window-toolbar">
        <div className="window-toolbar__leading">
          <div className="window-controls" aria-hidden="true">
            <span className="window-control window-control--close" />
            <span className="window-control window-control--minimize" />
            <span className="window-control window-control--zoom" />
          </div>
          <div className="app-shell__title-group">
            <strong>{title}</strong>
            <p className="muted">{subtitle}</p>
          </div>
        </div>
        <div className="app-shell__header-meta">
          {headerMeta}
          {headerActions}
        </div>
      </header>
      <aside className="app-shell__sidebar window-sidebar">{sidebar}</aside>
      <main id="main-content" className="app-shell__main window-content">
        {children}
      </main>
    </div>
  );
}
