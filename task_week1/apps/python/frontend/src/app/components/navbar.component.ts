import { Component, input } from '@angular/core';

// selector 'header[app-navbar]' = this component IS the <header app-navbar> element
// (no extra wrapper element), so the CSS (sticky .navbar) works exactly like in the React app.
@Component({
  selector: 'header[app-navbar]',
  host: { class: 'navbar' },
  template: `
    <div class="container navbar__inner">
      <a class="brand" href="#overview">
        <span class="brand__logo">N</span>
        Notely
      </a>
      <nav class="navbar__links">
        <a href="#overview">Overview</a>
        <a href="#notes">Notes</a>
      </nav>
      <span class="status" [class.status--ok]="online()" [class.status--down]="!online()">
        <i></i>
        {{ online() ? 'API online' : 'API offline' }}
      </span>
    </div>
  `,
})
export class NavbarComponent {
  online = input(true);
}
