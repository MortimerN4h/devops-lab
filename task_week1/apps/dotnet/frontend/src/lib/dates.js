// dueDate travels as a plain "YYYY-MM-DD" string (ISO 8601) and is shown as dd/mm/yyyy.
// We never call new Date("2026-11-20"): that is parsed as UTC and can shift by a day.

const pad = (n) => String(n).padStart(2, '0');

export function todayISO() {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// "2026-11-25" -> "25/11/2026" (day first, as used in Vietnam).
export function formatDue(iso) {
  return iso.split('-').reverse().join('/');
}

// Returns { tone, label } for the badge, or null when the note has no due date.
export function dueStatus(note) {
  if (!note.dueDate) return null;
  const today = todayISO();
  const label = formatDue(note.dueDate);
  if (note.done) return { tone: 'neutral', label: `Due ${label}` };
  if (note.dueDate < today) return { tone: 'overdue', label: `Overdue · ${label}` };
  if (note.dueDate === today) return { tone: 'today', label: 'Due today' };
  return { tone: 'upcoming', label: `Due ${label}` };
}
