function Stat({ label, value, hint }) {
  return (
    <div className="stat">
      <span className="stat__label">{label}</span>
      <strong className="stat__value">{value}</strong>
      <span className="stat__hint">{hint}</span>
    </div>
  );
}

export default function Hero({ total, done }) {
  const remaining = total - done;
  const pct = total ? Math.round((done / total) * 100) : 0;

  return (
    <section className="hero" id="overview">
      <div className="container">
        <span className="eyebrow">Notes made simple</span>
        <h1>
          Capture ideas. <span>Ship them.</span>
        </h1>
        <p className="hero__sub">
          A tiny full-stack app used to practise building, containerising and deploying
          the same product on different technology stacks.
        </p>

        <div className="stats">
          <Stat label="Total notes" value={total} hint="stored in the database" />
          <Stat label="Completed" value={done} hint="marked as done" />
          <Stat label="Remaining" value={remaining} hint="still to do" />
          <div className="stat stat--progress">
            <span className="stat__label">Progress</span>
            <strong className="stat__value">{pct}%</strong>
            <div className="bar">
              <div className="bar__fill" style={{ width: `${pct}%` }} />
            </div>
          </div>
        </div>
      </div>
    </section>
  );
}
