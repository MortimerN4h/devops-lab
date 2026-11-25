import { Component, inject } from '@angular/core';
import { NotesStore } from '../notes.store';

@Component({
  selector: 'div[app-toasts]',
  host: { class: 'toasts', 'aria-live': 'polite' },
  template: `
    @for (t of store.toasts(); track t.id) {
      <div class="toast" [class]="'toast--' + t.type">{{ t.message }}</div>
    }
  `,
})
export class ToastsComponent {
  protected store = inject(NotesStore);
}
