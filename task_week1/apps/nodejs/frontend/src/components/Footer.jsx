export default function Footer() {
  return (
    <footer className="footer">
      <div className="container footer__inner">
        <div>
          <strong>Notely</strong>
          <p>A DevOps practice project: one app, many stacks.</p>
        </div>
        <p className="footer__copy">© {new Date().getFullYear()} Notely. All rights reserved.</p>
      </div>
    </footer>
  );
}
