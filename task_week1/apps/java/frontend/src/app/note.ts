// Shapes from API.md. `id` is a number here (PostgreSQL) but a string for MongoDB: never parse it.
export interface Note {
  id: string | number;
  text: string;
  done: boolean;
  dueDate: string | null; // "YYYY-MM-DD"
  createdAt: string;
}

export interface NoteInput {
  text: string;
  done?: boolean;
  dueDate: string | null;
}

export interface Toast {
  id: number;
  type: 'success' | 'error';
  message: string;
}
