"""Notes API with FastAPI + PostgreSQL. Same contract as every other backend: ../../../API.md"""
import json
import logging
import os
import re
from contextlib import asynccontextmanager
from datetime import date, timezone

from fastapi import FastAPI, Request
from fastapi.responses import JSONResponse, Response
from psycopg.rows import dict_row
from psycopg_pool import AsyncConnectionPool
from starlette.exceptions import HTTPException as StarletteHTTPException

DATABASE_URL = os.getenv("DATABASE_URL", "postgresql://notes:notes@localhost:5432/notesdb")
log = logging.getLogger("uvicorn.error")

# A POOL keeps a few database connections open and lends them to requests,
# instead of opening a new connection (slow) for every request.
pool = AsyncConnectionPool(DATABASE_URL, min_size=1, max_size=5, open=False,
                           kwargs={"row_factory": dict_row})  # rows come back as dicts


@asynccontextmanager
async def lifespan(app: FastAPI):
    await pool.open(wait=True, timeout=30)  # at startup: connect (fail fast if the DB is unreachable)
    yield
    await pool.close()                      # at shutdown: close connections cleanly


# Swagger UI under /api/docs, so it also works through the nginx proxy (which only forwards /api/...)
app = FastAPI(title="Notes API (Python)", lifespan=lifespan,
              docs_url="/api/docs", openapi_url="/api/openapi.json", redoc_url=None)


# ---- Errors: every failure becomes {"error": {"code", "message"}} ----
class ApiError(Exception):
    def __init__(self, status: int, code: str, message: str):
        self.status, self.code, self.message = status, code, message


def not_found(note_id) -> ApiError:
    return ApiError(404, "NOT_FOUND", f"Note {note_id} not found")


def invalid(message: str) -> ApiError:
    return ApiError(400, "VALIDATION_ERROR", message)


def error_response(status: int, code: str, message: str) -> JSONResponse:
    return JSONResponse({"error": {"code": code, "message": message}}, status_code=status)


@app.exception_handler(ApiError)
async def api_error_handler(request: Request, err: ApiError):
    return error_response(err.status, err.code, err.message)


@app.exception_handler(StarletteHTTPException)
async def http_error_handler(request: Request, err: StarletteHTTPException):
    # Unknown route (404) or wrong method (405): answer 404 JSON like the other backends.
    return error_response(404, "NOT_FOUND", f"Route {request.url.path} not found")


@app.exception_handler(Exception)
async def unexpected_error_handler(request: Request, err: Exception):
    log.exception("Unexpected error")  # full stack trace goes to the logs, never to the client
    return error_response(500, "INTERNAL_ERROR", "Unexpected server error")


# ---- Helpers ----
def to_note(row: dict) -> dict:
    """Database row (snake_case) -> API JSON (camelCase), same shape as API.md."""
    created = row["created_at"].astimezone(timezone.utc).isoformat(timespec="milliseconds")
    return {
        "id": row["id"],
        "text": row["text"],
        "done": row["done"],
        "dueDate": row["due_date"].isoformat() if row["due_date"] else None,
        "createdAt": created.replace("+00:00", "Z"),
    }


def parse_id(raw: str):
    """A malformed id ("does-not-exist") is treated as "not found", like every backend."""
    if re.fullmatch(r"[0-9]{1,18}", raw):  # fits in BIGINT
        return int(raw)
    return None


def parse_due_date(value):
    """dueDate: missing/null -> None, otherwise a REAL date "YYYY-MM-DD" (2026-02-30 is rejected)."""
    if value is None:
        return None
    bad = invalid("dueDate must be a date in YYYY-MM-DD format or null")
    if not isinstance(value, str) or not re.fullmatch(r"[0-9]{4}-[0-9]{2}-[0-9]{2}", value):
        raise bad
    try:
        return date.fromisoformat(value)  # raises ValueError for impossible dates
    except ValueError:
        raise bad from None


def validate(body) -> dict:
    if not isinstance(body, dict):
        body = {}
    text = body.get("text")
    text = text.strip() if isinstance(text, str) else ""
    if not text:
        raise invalid("text is required")
    if len(text) > 200:
        raise invalid("text must be at most 200 characters")
    done = body.get("done", False)
    if type(done) is not bool:  # isinstance(1, bool) is False, but True is also an int: check the exact type
        raise invalid("done must be a boolean")
    return {"text": text, "done": done, "due_date": parse_due_date(body.get("dueDate"))}


async def read_json(request: Request):
    # We read the body ourselves (instead of a Pydantic model) to return exactly the
    # error codes of API.md: INVALID_JSON / VALIDATION_ERROR with status 400 (FastAPI's default is 422).
    try:
        return json.loads(await request.body())
    except ValueError:
        raise ApiError(400, "INVALID_JSON", "Request body is not valid JSON") from None


# ---- Routes ----
@app.get("/api/health")
async def health():
    return {"status": "ok", "backend": "Python + FastAPI + PostgreSQL"}


@app.get("/api/notes")
async def list_notes():
    async with pool.connection() as conn:
        rows = await (await conn.execute("SELECT * FROM notes ORDER BY id DESC")).fetchall()
    return [to_note(r) for r in rows]


@app.get("/api/notes/{note_id}")
async def get_note(note_id: str):
    nid = parse_id(note_id)
    row = None
    if nid is not None:
        async with pool.connection() as conn:
            # %s = placeholder: psycopg sends the value separately -> no SQL injection
            row = await (await conn.execute("SELECT * FROM notes WHERE id = %s", (nid,))).fetchone()
    if row is None:
        raise not_found(note_id)
    return to_note(row)


@app.post("/api/notes", status_code=201)
async def create_note(request: Request):
    note = validate(await read_json(request))
    async with pool.connection() as conn:
        row = await (await conn.execute(
            "INSERT INTO notes (text, done, due_date) VALUES (%(text)s, %(done)s, %(due_date)s) RETURNING *",
            note,
        )).fetchone()
    return to_note(row)


@app.put("/api/notes/{note_id}")
async def update_note(note_id: str, request: Request):
    nid = parse_id(note_id)
    if nid is None:
        raise not_found(note_id)
    note = validate(await read_json(request))  # full replace: missing dueDate -> NULL
    async with pool.connection() as conn:
        row = await (await conn.execute(
            "UPDATE notes SET text = %(text)s, done = %(done)s, due_date = %(due_date)s"
            " WHERE id = %(id)s RETURNING *",
            {**note, "id": nid},
        )).fetchone()
    if row is None:
        raise not_found(note_id)
    return to_note(row)


@app.delete("/api/notes/{note_id}", status_code=204)
async def delete_note(note_id: str):
    nid = parse_id(note_id)
    deleted = None
    if nid is not None:
        async with pool.connection() as conn:
            deleted = await (await conn.execute("DELETE FROM notes WHERE id = %s RETURNING id", (nid,))).fetchone()
    if deleted is None:
        raise not_found(note_id)
    return Response(status_code=204)
