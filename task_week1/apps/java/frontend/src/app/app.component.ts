import { Component, OnInit, computed, inject, signal } from '@angular/core';
import { NotesStore } from './notes.store';
import { NavbarComponent } from './components/navbar.component';
import { HeroComponent } from './components/hero.component';
import { ComposerComponent } from './components/composer.component';
import { NoteItemComponent } from './components/note-item.component';
import { ToastsComponent } from './components/toasts.component';
import { FooterComponent } from './components/footer.component';

type Filter = 'all' | 'active' | 'done';

@Component({
  selector: 'app-root',
  imports: [NavbarComponent, HeroComponent, ComposerComponent, NoteItemComponent, ToastsComponent, FooterComponent],
  template: `
    <header app-navbar [online]="store.online()"></header>
    <section app-hero [total]="store.notes().length" [done]="store.doneCount()"></section>

    <main class="container main" id="notes">
      <section class="panel">
        <h2>New note</h2>
        <form app-composer></form>
      </section>

      <section class="panel">
        <div class="toolbar">
          <h2>Your notes</h2>
          <div class="toolbar__controls">
            <input
              class="search"
              type="search"
              placeholder="Search notes…"
              [value]="query()"
              (input)="query.set($any($event.target).value)"
            />
            <div class="tabs">
              @for (f of filters; track f.key) {
                <button class="tab" [class.tab--active]="filter() === f.key" (click)="filter.set(f.key)">
                  {{ f.label }}
                </button>
              }
            </div>
          </div>
        </div>

        @if (store.loading()) {
          <div class="skeletons">
            <div class="skeleton"></div><div class="skeleton"></div><div class="skeleton"></div>
          </div>
        } @else if (visible().length === 0) {
          <div class="empty">
            <strong>{{ store.notes().length === 0 ? 'No notes yet' : 'No notes match' }}</strong>
            <p>
              {{ store.notes().length === 0 ? 'Add your first note above to get started.' : 'Try a different search or filter.' }}
            </p>
          </div>
        } @else {
          <ul class="notes">
            @for (n of visible(); track n.id) {
              <li app-note-item [note]="n"></li>
            }
          </ul>
        }
      </section>
    </main>

    <footer app-footer></footer>
    <div app-toasts></div>
  `,
})
export class AppComponent implements OnInit {
  protected store = inject(NotesStore);

  protected filters: { key: Filter; label: string }[] = [
    { key: 'all', label: 'All' },
    { key: 'active', label: 'Active' },
    { key: 'done', label: 'Completed' },
  ];
  protected filter = signal<Filter>('all');
  protected query = signal('');

  // computed() = derived value, recalculated only when notes, filter or query change.
  protected visible = computed(() => {
    const q = this.query().trim().toLowerCase();
    return this.store
      .notes()
      .filter((n) => (this.filter() === 'all' ? true : this.filter() === 'done' ? n.done : !n.done))
      .filter((n) => n.text.toLowerCase().includes(q));
  });

  ngOnInit() {
    this.store.init();
  }
}
