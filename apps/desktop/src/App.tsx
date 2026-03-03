import { AppShell } from './ui/layout/AppShell';

export function App() {
  return (
    <AppShell
      title="FluxDeck Admin"
      sidebar={
        <section>
          <h2>Sidebar</h2>
          <p className="muted">Provider / Gateway / Logs</p>
        </section>
      }
    >
      <section className="app-card">
        <h2>Providers</h2>
        <p className="muted">No providers yet.</p>
      </section>

      <section className="app-card">
        <h2>Gateways</h2>
        <p className="muted">No gateways yet.</p>
      </section>

      <section className="app-card">
        <h2>Logs</h2>
        <p className="muted">No logs yet.</p>
      </section>
    </AppShell>
  );
}

export default App;
