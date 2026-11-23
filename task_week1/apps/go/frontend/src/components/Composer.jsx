import { useState } from 'react';
import { todayISO } from '../lib/dates';
import DateInput from './DateInput.jsx';

export default function Composer({ onAdd }) {
  const [text, setText] = useState('');
  const [dueDate, setDueDate] = useState('');
  const [busy, setBusy] = useState(false);

  const submit = async (e) => {
    e.preventDefault();
    setBusy(true);
    // Empty date input -> null ("no deadline"), as the API contract expects.
    const ok = await onAdd({ text, dueDate: dueDate || null });
    setBusy(false);
    if (ok) {
      setText('');
      setDueDate('');
    }
  };

  return (
    <form className="composer" onSubmit={submit}>
      <div className="composer__field">
        <input
          value={text}
          onChange={(e) => setText(e.target.value)}
          placeholder="What do you want to remember?"
          maxLength={200}
          aria-label="New note"
        />
        <span className="composer__count">{text.length}/200</span>
      </div>

      <div className="datefield">
        <span>Due date</span>
        <DateInput value={dueDate} min={todayISO()} onChange={setDueDate} ariaLabel="Due date" />
      </div>

      <button className="btn btn--primary" disabled={busy}>
        {busy ? 'Adding…' : 'Add note'}
      </button>
    </form>
  );
}
