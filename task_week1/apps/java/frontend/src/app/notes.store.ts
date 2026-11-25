import { Injectable, computed, inject, signal } from '@angular/core';
import { ApiService } from './api.service';
import { Note, NoteInput, Toast } from './note';

const messageOf = (e: unknown) => (e instanceof Error ? e.message : String(e));

// The app's state in one place. Components read the signals and call the methods;
// a signal re-renders every template that uses it when its value changes.
@Injectable({ providedIn: 'root' })
export class NotesStore {
  private api = inject(ApiService);

  readonly notes = signal<Note[]>([]);
  readonly loading = signal(true);
  readonly online = signal(true);
  readonly toasts = signal<Toast[]>([]);
  readonly doneCount = computed(() => this.notes().filter((n) => n.done).length);

  async init() {
    this.api.health().then(() => this.online.set(true), () => this.online.set(false));
    try {
      await this.load();
    } catch (e) {
      this.toast('error', messageOf(e));
    } finally {
      this.loading.set(false);
    }
  }

  add(note: NoteInput) {
    return this.act(() => this.api.create(note), 'Note added');
  }

  toggle(note: Note) {
    return this.act(() => this.api.update(note.id, { text: note.text, done: !note.done, dueDate: note.dueDate }));
  }

  save(note: Note, changes: { text: string; dueDate: string | null }) {
    return this.act(() => this.api.update(note.id, { ...changes, done: note.done }), 'Note updated');
  }

  remove(note: Note) {
    return this.act(() => this.api.remove(note.id), 'Note deleted');
  }

  private async load() {
    this.notes.set(await this.api.list());
  }

  // Run an API action, reload the list, show a toast. Returns true on success
  // so a component knows whether to close its form.
  private async act(action: () => Promise<unknown>, successMessage?: string): Promise<boolean> {
    try {
      await action();
      await this.load();
      if (successMessage) this.toast('success', successMessage);
      return true;
    } catch (e) {
      this.toast('error', messageOf(e));
      return false;
    }
  }

  private toast(type: Toast['type'], message: string) {
    const id = Date.now() + Math.random();
    this.toasts.update((list) => [...list, { id, type, message }]);
    setTimeout(() => this.toasts.update((list) => list.filter((t) => t.id !== id)), 3500);
  }
}
