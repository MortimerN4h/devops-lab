export default function Navbar({ online }) {
  return (
    <header className="navbar">
      <div className="container navbar__inner">
        <a className="brand" href="#overview">
          <span className="brand__logo">N</span>
          Notely
        </a>
        <nav className="navbar__links">
          <a href="#overview">Overview</a>
          <a href="#notes">Notes</a>
        </nav>
        <span className={`status ${online ? 'status--ok' : 'status--down'}`}>
          <i />
          {online ? 'API online' : 'API offline'}
        </span>
      </div>
    </header>
  );
}
