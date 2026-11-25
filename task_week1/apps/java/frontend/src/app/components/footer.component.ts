import { Component } from '@angular/core';

@Component({
  selector: 'footer[app-footer]',
  host: { class: 'footer' },
  template: `
    <div class="container footer__inner">
      <div>
        <strong>Notely</strong>
        <p>A DevOps practice project: one app, many stacks.</p>
      </div>
      <p class="footer__copy">© {{ year }} Notely. All rights reserved.</p>
    </div>
  `,
})
export class FooterComponent {
  protected year = new Date().getFullYear();
}
