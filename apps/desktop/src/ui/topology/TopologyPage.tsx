import { TopologyCanvas } from './TopologyCanvas';

export function TopologyPage() {
  return (
    <section className="app-card" id="topology">
      <div className="section-heading">
        <div>
          <p className="eyebrow">Topology</p>
          <h2>Topology workspace</h2>
          <p className="muted">Inspect routing relationships across gateways, providers, and models.</p>
        </div>
        <span className="count-pill">Live Flow</span>
      </div>
      <div className="pill-row">
        <span className="info-pill">Live Flow</span>
        <span className="info-pill">Failure Path</span>
        <span className="info-pill">Gateways</span>
        <span className="info-pill">Providers</span>
        <span className="info-pill">Models</span>
      </div>
      <TopologyCanvas />
    </section>
  );
}
