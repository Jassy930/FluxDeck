type TopologyNodeProps = {
  name: string;
  meta: string;
  tone?: 'entry' | 'gateway' | 'provider' | 'model';
};

export function TopologyNode({ name, meta, tone = 'entry' }: TopologyNodeProps) {
  return (
    <article className={`topology-node topology-node--${tone}`}>
      <h3>{name}</h3>
      <p className="muted">{meta}</p>
    </article>
  );
}
