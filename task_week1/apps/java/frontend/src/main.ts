import { bootstrapApplication } from '@angular/platform-browser';
import { provideHttpClient, withFetch } from '@angular/common/http';
import { AppComponent } from './app/app.component';

// Start the app: render <app-root> and register the HTTP client used by ApiService.
bootstrapApplication(AppComponent, {
  providers: [provideHttpClient(withFetch())],
}).catch((err) => console.error(err));
