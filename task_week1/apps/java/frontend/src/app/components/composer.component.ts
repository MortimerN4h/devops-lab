import { Component, inject, signal } from '@angular/core';
import { NotesStore } from '../notes.store';
import { todayISO } from '../dates';
import { DateInputComponent } from './date-input.component';

@Component({
  selector: 'form[app-composer]',
  imports: [DateInputComponent],
  host: { class: 'composer', '(submit)': 'submit($event)' },
  template: `
    <div class="composer__field">
      <input
        [value]="text()"
        (input)="text.set($any($event.target).value)"
        placeholder="What do you want to remember?"
        maxlength="200"
        aria-label="New note"
      />
      <span class="composer__count">{{ text().length }}/200</span>
    </div>

    <div class="datefield">
      <span>Due date</span>
      <div app-date-input [(value)]="dueDate" [min]="today" ariaLabel="Due date"></div>
    </div>

    <button class="btn btn--primary" [disabled]="busy()">{{ busy() ? 'Adding…' : 'Add note' }}</button>
  `,
})
export class ComposerComponent {
  private store = inject(NotesStore);

  protected text = signal('');
  protected dueDate = signal('');
  protected busy = signal(false);
  protected today = todayISO();

  protected async submit(event: Event) {
    event.preventDefault(); // stop the browser from reloading the page
    this.busy.set(true);
    // Empty date -> null ("no deadline"), as the API contract expects.
    const ok = await this.store.add({ text: this.text(), dueDate: this.dueDate() || null });
    this.busy.set(false);
    if (ok) {
      this.text.set('');
      this.dueDate.set('');
    }
  }
}
