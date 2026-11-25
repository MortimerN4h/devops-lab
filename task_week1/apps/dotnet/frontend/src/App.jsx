import { useEffect, useMemo, useState } from 'react';
import { api } from './api';
import Navbar from './components/Navbar.jsx';
import Hero from './components/Hero.jsx';
import Composer from './components/Composer.jsx';
import NoteItem from './components/NoteItem.jsx';
import Toasts from './components/Toasts.jsx';
import Footer from './components/Footer.jsx';
import './App.css';

const FILTERS = [
  { key: 'all', label: 'All' },
  { key: 'active', label: 'Active' },
  { key: 'done', label: 'Completed' },
];

export default function App() {
  const [notes, setNotes] = useState([]);
  const [loading, setLoading] = useState(true);
  const [online, setOnline] = useState(true);
  const [filter, setFilter] = useState('all');
  const [query, setQuery] = useState('');
  const [toasts, setToasts] = useState([]);

  const toast = (type, message) => {
    const id = Date.now() + Math.random();
    setToasts((list) => [...list, { id, type, message }]);
    setTimeout(() => setToasts((list) => list.filter((t) => t.id !== id)), 3500);
  };

  const load = async () => setNotes(await api.list());

  // Run an API action, reload the list, and show a toast with the result.
  // Returns true on success so child components know whether to close their form.
  const act = async (action, successMessage) => {
    try {
      await action();
      await load();
      if (successMessage) toast('success', successMessage);
      return true;
    } catch (e) {
      toast('error', e.message);
      return false;
    }
  };

  useEffect(() => {
    load()
      .catch((e) => toast('error', e.message))
      .finally(() => setLoading(false));
    api.health()
      .then(() => setOnline(true))
      .catch(() => setOnline(false));
  }, []);

  const done = notes.filter((n) => n.done).length;

  const visible = useMemo(
    () =>
      notes
        .filter((n) => (filter === 'all' ? true : filter === 'done' ? n.done : !n.done))
        .filter((n) => n.text.toLowerCase().includes(query.trim().toLowerCase())),
    [notes, filter, query],
  );

  return (
    <>
      <Navbar online={online} />
      <Hero total={notes.length} done={done} />

      <main className="container main" id="notes">
        <section className="panel">
          <h2>New note</h2>
          <Composer onAdd={(note) => act(() => api.create(note), 'Note added')} />
        </section>

        <section className="panel">
          <div className="toolbar">
            <h2>Your notes</h2>
            <div className="toolbar__controls">
              <input
                className="search"
                type="search"
                placeholder="Search notes…"
                value={query}
                onChange={(e) => setQuery(e.target.value)}
              />
              <div className="tabs">
                {FILTERS.map((f) => (
                  <button
                    key={f.key}
                    className={`tab ${filter === f.key ? 'tab--active' : ''}`}
                    onClick={() => setFilter(f.key)}
                  >
                    {f.label}
                  </button>
                ))}
              </div>
            </div>
          </div>

          {loading ? (
            <div className="skeletons">
              <div className="skeleton" /><div className="skeleton" /><div className="skeleton" />
            </div>
          ) : visible.length === 0 ? (
            <div className="empty">
              <strong>{notes.length === 0 ? 'No notes yet' : 'No notes match'}</strong>
              <p>
                {notes.length === 0
                  ? 'Add your first note above to get started.'
                  : 'Try a different search or filter.'}
              </p>
            </div>
          ) : (
            <ul className="notes">
              {visible.map((n) => (
                <NoteItem
                  key={n.id}
                  note={n}
                  onToggle={(note) =>
                    act(() => api.update(note.id, { text: note.text, done: !note.done, dueDate: note.dueDate }))
                  }
                  onSave={(note, changes) =>
                    act(() => api.update(note.id, { ...changes, done: note.done }), 'Note updated')
                  }
                  onDelete={(note) => act(() => api.remove(note.id), 'Note deleted')}
                />
              ))}
            </ul>
          )}
        </section>
      </main>

      <Footer />
      <Toasts toasts={toasts} />
    </>
  );
}
