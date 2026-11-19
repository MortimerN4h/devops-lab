import { Injectable, inject } from '@angular/core';
import { HttpClient, HttpErrorResponse } from '@angular/common/http';
import { Observable, firstValueFrom } from 'rxjs';
import { Note, NoteInput } from './note';

// All calls go to /api/... on the same origin; nginx forwards them to the backend.
@Injectable({ providedIn: 'root' })
export class ApiService {
  private http = inject(HttpClient);

  health() { return this.call(this.http.get<{ status: string; backend: string }>('/api/health')); }
  list() { return this.call(this.http.get<Note[]>('/api/notes')); }
  create(note: NoteInput) { return this.call(this.http.post<Note>('/api/notes', note)); }
  update(id: Note['id'], note: NoteInput) { return this.call(this.http.put<Note>(`/api/notes/${id}`, note)); }
  remove(id: Note['id']) { return this.call(this.http.delete<null>(`/api/notes/${id}`)); }

  // HttpClient returns an Observable; turn it into a Promise and use the API's error message.
  private async call<T>(request: Observable<T>): Promise<T> {
    try {
      return await firstValueFrom(request);
    } catch (e) {
      if (e instanceof HttpErrorResponse) {
        throw new Error(e.error?.error?.message ?? `HTTP ${e.status}`);
      }
      throw e;
    }
  }
}
