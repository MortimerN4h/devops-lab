import { Component, ElementRef, computed, effect, input, model, signal, untracked, viewChild } from '@angular/core';
import { ISO_DATE, displayToIso } from '../dates';

// A date field that always shows dd/mm/yyyy, whatever the browser language is.
// The native <input type="date"> follows the browser locale (mm/dd/yyyy in en-US),
// so we show our own text box and keep a hidden native input only for its calendar popup.
// `value` uses the API format "YYYY-MM-DD" ('' = no date). It is a model(): the parent
// binds it two-way with [(value)]="someSignal".

const isoToDisplay = (v: string) => (ISO_DATE.test(v) ? v.split('-').reverse().join('/') : v);

// Keep digits only and insert the slashes: "2511" -> "25/11"
function mask(raw: string): string {
  const digits = raw.replace(/\D/g, '').slice(0, 8);
  return [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4)].filter(Boolean).join('/');
}

@Component({
  selector: 'div[app-date-input]',
  host: { class: 'dateinput', '[class.dateinput--invalid]': 'invalid()' },
  template: `
    <input
      class="dateinput__text"
      [class]="inputClass()"
      inputmode="numeric"
      placeholder="dd/mm/yyyy"
      [value]="text()"
      (input)="onType($event)"
      [attr.aria-label]="ariaLabel()"
      [attr.aria-invalid]="invalid()"
      [attr.title]="invalid() ? 'This date does not exist' : null"
    />
    <button type="button" class="dateinput__btn" (click)="openPicker()" aria-label="Open calendar">
      <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"
           stroke-linecap="round" stroke-linejoin="round">
        <rect x="3" y="4" width="18" height="18" rx="2" />
        <path d="M16 2v4M8 2v4M3 10h18" />
      </svg>
    </button>
    <input
      #picker
      class="dateinput__native"
      type="date"
      tabindex="-1"
      aria-hidden="true"
      [attr.min]="min()"
      [value]="isoValue()"
      (change)="value.set($any($event.target).value)"
    />
  `,
})
export class DateInputComponent {
  value = model('');
  min = input<string | null>(null);
  inputClass = input('');
  ariaLabel = input('Date');

  protected text = signal('');
  private picker = viewChild.required<ElementRef<HTMLInputElement>>('picker');

  protected invalid = computed(() => this.text().length === 10 && !displayToIso(this.text()));
  protected isoValue = computed(() => (ISO_DATE.test(this.value()) ? this.value() : ''));

  constructor() {
    // Follow changes made by the parent (form reset, calendar pick) but not while the user is typing.
    effect(() => {
      const value = this.value();
      const current = untracked(this.text);
      if (value !== (displayToIso(current) ?? (current.length === 10 ? current : ''))) {
        this.text.set(isoToDisplay(value));
      }
    });
  }

  protected onType(event: Event) {
    const box = event.target as HTMLInputElement;
    const next = mask(box.value);
    box.value = next; // also fix the box when the mask removed a typed letter
    this.text.set(next);
    // Complete but impossible date: pass the raw text on, so the API answers 400 with a clear message.
    this.value.set(displayToIso(next) ?? (next.length === 10 ? next : ''));
  }

  protected openPicker() {
    const el = this.picker().nativeElement;
    try {
      el.showPicker();
    } catch {
      el.focus();
    }
  }
}
