// dueDate travels as a plain "YYYY-MM-DD" string (ISO 8601) and is shown as dd/mm/yyyy.
// We never call new Date("2026-11-20"): that is parsed as UTC and can shift by a day.
import { Note } from './note';

const pad = (n: number) => String(n).padStart(2, '0');

export const ISO_DATE = /^(\d{4})-(\d{2})-(\d{2})$/;

export function todayISO(): string {
  const d = new Date();
  return `${d.getFullYear()}-${pad(d.getMonth() + 1)}-${pad(d.getDate())}`;
}

// "2026-11-25" -> "25/11/2026" (day first, as used in Vietnam).
export function formatDue(iso: string): string {
  return iso.split('-').reverse().join('/');
}

// "25/11/2026" -> "2026-11-25", or null when incomplete / not a real date (31/02/2026).
export function displayToIso(text: string): string | null {
  const m = text.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!m) return null;
  const [, d, mo, y] = m;
  const date = new Date(+y, +mo - 1, +d);
  const real = date.getFullYear() === +y && date.getMonth() === +mo - 1 && date.getDate() === +d;
  return real ? `${y}-${mo}-${d}` : null;
}

export interface DueStatus {
  tone: 'overdue' | 'today' | 'upcoming' | 'neutral';
  label: string;
}

// Badge shown under a note, or null when the note has no due date.
export function dueStatus(note: Note): DueStatus | null {
  if (!note.dueDate) return null;
  const today = todayISO();
  const label = formatDue(note.dueDate);
  if (note.done) return { tone: 'neutral', label: `Due ${label}` };
  if (note.dueDate < today) return { tone: 'overdue', label: `Overdue · ${label}` };
  if (note.dueDate === today) return { tone: 'today', label: 'Due today' };
  return { tone: 'upcoming', label: `Due ${label}` };
}
