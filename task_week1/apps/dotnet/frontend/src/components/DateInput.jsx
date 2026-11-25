import { useEffect, useRef, useState } from 'react';

// A date field that always shows dd/mm/yyyy, whatever the browser language is.
// The native <input type="date"> follows the browser locale (mm/dd/yyyy in en-US),
// so we show our own text box and keep a hidden native input only for its calendar popup.
// `value` / `onChange` use the API format "YYYY-MM-DD" ('' = no date).

const ISO = /^(\d{4})-(\d{2})-(\d{2})$/;

const isoToDisplay = (v) => (ISO.test(v) ? v.split('-').reverse().join('/') : v);

// "25/11/2026" -> "2026-11-25", or null when incomplete / not a real date (31/02/2026).
function displayToIso(text) {
  const m = text.match(/^(\d{2})\/(\d{2})\/(\d{4})$/);
  if (!m) return null;
  const [, d, mo, y] = m;
  const date = new Date(+y, +mo - 1, +d);
  const real = date.getFullYear() === +y && date.getMonth() === +mo - 1 && date.getDate() === +d;
  return real ? `${y}-${mo}-${d}` : null;
}

// Keep digits only and insert the slashes: "2511" -> "25/11"
function mask(raw) {
  const digits = raw.replace(/\D/g, '').slice(0, 8);
  return [digits.slice(0, 2), digits.slice(2, 4), digits.slice(4)].filter(Boolean).join('/');
}

export default function DateInput({ value, onChange, min, className = '', wrapperClassName = '', ariaLabel = 'Date' }) {
  const [text, setText] = useState(isoToDisplay(value));
  const picker = useRef(null);

  // Follow changes made by the parent (form reset, calendar pick) but not while the user is typing.
  useEffect(() => {
    if (value !== (displayToIso(text) ?? (text.length === 10 ? text : ''))) setText(isoToDisplay(value));
  }, [value]); // eslint-disable-line react-hooks/exhaustive-deps

  const type = (e) => {
    const next = mask(e.target.value);
    setText(next);
    // Complete but impossible date: pass the raw text on, so the API answers 400 with a clear message.
    onChange(displayToIso(next) ?? (next.length === 10 ? next : ''));
  };

  const openPicker = () => {
    try {
      picker.current.showPicker();
    } catch {
      picker.current.focus();
    }
  };

  const invalid = text.length === 10 && !displayToIso(text);

  return (
    <div className={`dateinput ${invalid ? 'dateinput--invalid' : ''} ${wrapperClassName}`}>
      <input
        className={`dateinput__text ${className}`}
        inputMode="numeric"
        placeholder="dd/mm/yyyy"
        value={text}
        onChange={type}
        aria-label={ariaLabel}
        aria-invalid={invalid}
        title={invalid ? 'This date does not exist' : undefined}
      />
      <button type="button" className="dateinput__btn" onClick={openPicker} aria-label="Open calendar">
        <svg width="18" height="18" viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth="2" strokeLinecap="round" strokeLinejoin="round">
          <rect x="3" y="4" width="18" height="18" rx="2" />
          <path d="M16 2v4M8 2v4M3 10h18" />
        </svg>
      </button>
      <input
        ref={picker}
        className="dateinput__native"
        type="date"
        tabIndex={-1}
        aria-hidden="true"
        min={min}
        value={ISO.test(value) ? value : ''}
        onChange={(e) => onChange(e.target.value)}
      />
    </div>
  );
}
