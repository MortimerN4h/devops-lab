import { Component, ElementRef, computed, inject, input, signal, viewChild } from '@angular/core';
import { NotesStore } from '../notes.store';
import { Note } from '../note';
import { dueStatus } from '../dates';
import { DateInputComponent } from './date-input.component';

@Component({
  selector: 'li[app-note-item]',
  imports: [DateInputComponent],
  host: { class: 'note', '[class.note--done]': 'note().done' },
  template: `
    <input class="note__check" type="checkbox" [checked]="note().done" (change)="toggle($event)" aria-label="Mark as done" />

    <div class="note__body">
      @if (editing()) {
        <div class="note__editrow">
          <input
            #edit
            class="note__edit"
            [value]="draft()"
            maxlength="200"
            (input)="draft.set($any($event.target).value)"
            (keydown.enter)="save()"
            (keydown.escape)="editing.set(false)"
          />
          <div app-date-input class="note__edit--date" inputClass="note__edit" [(value)]="draftDue" ariaLabel="Due date"></div>
        </div>
      } @else {
        <p class="note__text">{{ note().text }}</p>
        @if (due(); as d) {
          <span class="badge" [class]="'badge--' + d.tone">{{ d.label }}</span>
        }
      }
    </div>

    <div class="note__actions">
      @if (editing()) {
        <button class="btn btn--small btn--primary" (click)="save()">Save</button>
        <button class="btn btn--small btn--ghost" (click)="editing.set(false)">Cancel</button>
      } @else {
        <button class="btn btn--small btn--ghost" (click)="startEdit()">Edit</button>
        <button class="btn btn--small btn--danger" (click)="store.remove(note())">Delete</button>
      }
    </div>
  `,
})
export class NoteItemComponent {
  note = input.required<Note>();

  protected store = inject(NotesStore);
  protected editing = signal(false);
  protected draft = signal('');
  protected draftDue = signal('');
  protected due = computed(() => dueStatus(this.note()));
  private editBox = viewChild<ElementRef<HTMLInputElement>>('edit');

  protected startEdit() {
    this.draft.set(this.note().text);
    this.draftDue.set(this.note().dueDate ?? '');
    this.editing.set(true);
    setTimeout(() => this.editBox()?.nativeElement.focus()); // focus once the input is on screen
  }

  protected async save() {
    const ok = await this.store.save(this.note(), { text: this.draft(), dueDate: this.draftDue() || null });
    if (ok) this.editing.set(false);
  }

  protected async toggle(event: Event) {
    const box = event.target as HTMLInputElement;
    const ok = await this.store.toggle(this.note());
    if (!ok) box.checked = this.note().done; // API failed: put the checkbox back
  }
}
