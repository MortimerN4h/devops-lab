# Notes API contract

Every backend (Node, Python, Go, PHP, Spring, Quarkus, Rails) implements the same API,
so the same frontend and the same test script work against all of them.

Base path: `/api`. Request and response bodies are JSON (`Content-Type: application/json`).

## Note object

```json
{ "id": "…", "text": "Learn Docker", "done": false, "dueDate": "2026-11-30", "createdAt": "2026-11-17T04:00:00.000Z" }
```

`id` is opaque: a string for MongoDB, a number for SQL databases. Clients never parse it.
`dueDate` is a calendar date `YYYY-MM-DD` (no time, no timezone) or `null` when the note has no deadline.
`createdAt` is set by the server (ISO 8601 timestamp) and is used for sorting.

## Endpoints

| Method | Path              | Body                         | Success                    | Errors        |
|--------|-------------------|------------------------------|----------------------------|---------------|
| GET    | `/api/health`     | -                            | `200 {"status":"ok","backend":"…"}` | -     |
| GET    | `/api/notes`      | -                            | `200 [Note, …]` (newest first)       | -     |
| GET    | `/api/notes/{id}` | -                            | `200 Note`                 | 404           |
| POST   | `/api/notes`      | `{"text": "…", "dueDate": "YYYY-MM-DD"}` | `201 Note`     | 400           |
| PUT    | `/api/notes/{id}` | `{"text": "…", "done": bool, "dueDate": "YYYY-MM-DD"}` | `200 Note` (full replace) | 400, 404 |
| DELETE | `/api/notes/{id}` | -                            | `204` (no body)            | 404           |

Validation: `text` is required, a string, 1 to 200 characters after trimming. `done` is optional
(default `false`) and must be a boolean. `dueDate` is optional (default `null`); when present it must be
`null` or a real calendar date in `YYYY-MM-DD` format (`2026-02-30` is rejected).
PUT is a full replace: a field left out goes back to its default (so omitting `dueDate` clears it).

## Error format

Every error uses the same JSON shape:

```json
{ "error": { "code": "NOT_FOUND", "message": "Note abc not found" } }
```

| HTTP status | `code`             | When                                            |
|-------------|--------------------|-------------------------------------------------|
| 400         | `VALIDATION_ERROR` | `text` missing/empty/too long, `done` not boolean, bad `dueDate` |
| 400         | `INVALID_JSON`     | request body is not valid JSON                  |
| 404         | `NOT_FOUND`        | note does not exist, malformed id, or unknown `/api/...` route |
| 500         | `INTERNAL_ERROR`   | unexpected server error (never leak stack traces) |

A malformed id (for example `does-not-exist`) is treated as 404, so all backends behave the same.
