import { TopologyNode } from './TopologyNode';

const LAYERS = [
  {
    title: 'Entrypoints',
    tone: 'entry' as const,
    items: [
      { name: 'Desktop', meta: 'Local Admin UI' },
      { name: 'CLI', meta: 'fluxctl / scripts' },
    ],
  },
  {
    title: 'Gateways',
    tone: 'gateway' as const,
    items: [
      { name: 'gateway_main', meta: 'OpenAI inbound' },
      { name: 'gateway_map', meta: 'Anthropic compatible' },
    ],
  },
  {
    title: 'Providers',
    tone: 'provider' as const,
    items: [
      { name: 'provider_main', meta: 'Primary upstream' },
      { name: 'provider_backup', meta: 'Failover path' },
    ],
  },
  {
    title: 'Models',
    tone: 'model' as const,
    items: [
      { name: 'gpt-4o-mini', meta: 'Default model' },
      { name: 'qwen3-coder-plus', meta: 'Mapped route' },
    ],
  },
];

export function TopologyCanvas() {
  return (
    <section className="topology-canvas">
      <div className="topology-canvas__grid">
        {LAYERS.map((layer) => (
          <div key={layer.title} className="topology-layer">
            <h3>{layer.title}</h3>
            <div className="topology-layer__nodes">
              {layer.items.map((item) => (
                <TopologyNode key={item.name} name={item.name} meta={item.meta} tone={layer.tone} />
              ))}
            </div>
          </div>
        ))}
        <svg className="topology-canvas__paths" viewBox="0 0 800 280" aria-label="Topology flow paths" role="img">
          <path d="M120 72 C210 72, 230 72, 320 72 S430 72, 520 72 S640 72, 720 72" className="topology-canvas__path topology-canvas__path--primary" />
          <path d="M120 202 C210 202, 230 160, 320 160 S430 160, 520 116 S640 116, 720 158" className="topology-canvas__path topology-canvas__path--secondary" />
        </svg>
      </div>
      <aside className="topology-detail-panel">
        <p className="eyebrow">Selected Route</p>
        <h3>gateway_map → provider_main</h3>
        <p className="muted">Fallback-aware route carrying Anthropic-compatible traffic into the primary upstream pool.</p>
        <div className="pill-row">
          <span className="info-pill">Healthy</span>
          <span className="info-pill">128 rpm</span>
          <span className="info-pill">48 ms P95</span>
        </div>
      </aside>
    </section>
  );
}
