import { Component, computed, input } from '@angular/core';

@Component({
  selector: 'section[app-hero]',
  host: { class: 'hero', id: 'overview' },
  template: `
    <div class="container">
      <span class="eyebrow">Notes made simple</span>
      <h1>Capture ideas. <span>Ship them.</span></h1>
      <p class="hero__sub">
        A tiny full-stack app used to practise building, containerising and deploying
        the same product on different technology stacks.
      </p>

      <div class="stats">
        @for (s of stats(); track s.label) {
          <div class="stat">
            <span class="stat__label">{{ s.label }}</span>
            <strong class="stat__value">{{ s.value }}</strong>
            <span class="stat__hint">{{ s.hint }}</span>
          </div>
        }
        <div class="stat stat--progress">
          <span class="stat__label">Progress</span>
          <strong class="stat__value">{{ pct() }}%</strong>
          <div class="bar">
            <div class="bar__fill" [style.width.%]="pct()"></div>
          </div>
        </div>
      </div>
    </div>
  `,
})
export class HeroComponent {
  total = input.required<number>();
  done = input.required<number>();

  pct = computed(() => (this.total() ? Math.round((this.done() / this.total()) * 100) : 0));
  stats = computed(() => [
    { label: 'Total notes', value: this.total(), hint: 'stored in the database' },
    { label: 'Completed', value: this.done(), hint: 'marked as done' },
    { label: 'Remaining', value: this.total() - this.done(), hint: 'still to do' },
  ]);
}
