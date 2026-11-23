import { useState } from 'react';
import { dueStatus } from '../lib/dates';
import DateInput from './DateInput.jsx';

export default function NoteItem({ note, onToggle, onSave, onDelete }) {
  const [editing, setEditing] = useState(false);
  const [draft, setDraft] = useState(note.text);
  const [draftDue, setDraftDue] = useState(note.dueDate || '');

  const startEdit = () => {
    setDraft(note.text);
    setDraftDue(note.dueDate || '');
    setEditing(true);
  };

  const save = async () => {
    const ok = await onSave(note, { text: draft, dueDate: draftDue || null });
    if (ok) setEditing(false);
  };

  const due = dueStatus(note);

  return (
    <li className={`note ${note.done ? 'note--done' : ''}`}>
      <input
        className="note__check"
        type="checkbox"
        checked={note.done}
        onChange={() => onToggle(note)}
        aria-label="Mark as done"
      />

      <div className="note__body">
        {editing ? (
          <div className="note__editrow">
            <input
              className="note__edit"
              value={draft}
              maxLength={200}
              onChange={(e) => setDraft(e.target.value)}
              onKeyDown={(e) => {
                if (e.key === 'Enter') save();
                if (e.key === 'Escape') setEditing(false);
              }}
              autoFocus
            />
            <DateInput
              className="note__edit"
              wrapperClassName="note__edit--date"
              value={draftDue}
              onChange={setDraftDue}
              ariaLabel="Due date"
            />
          </div>
        ) : (
          <>
            <p className="note__text">{note.text}</p>
            {due && <span className={`badge badge--${due.tone}`}>{due.label}</span>}
          </>
        )}
      </div>

      <div className="note__actions">
        {editing ? (
          <>
            <button className="btn btn--small btn--primary" onClick={save}>Save</button>
            <button className="btn btn--small btn--ghost" onClick={() => setEditing(false)}>Cancel</button>
          </>
        ) : (
          <>
            <button className="btn btn--small btn--ghost" onClick={startEdit}>Edit</button>
            <button className="btn btn--small btn--danger" onClick={() => onDelete(note)}>Delete</button>
          </>
        )}
      </div>
    </li>
  );
}
