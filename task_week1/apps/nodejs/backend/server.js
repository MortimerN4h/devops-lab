const express = require('express');
const { MongoClient, ObjectId } = require('mongodb');

const PORT = process.env.PORT || 3000;
const MONGO_URL = process.env.MONGO_URL || 'mongodb://localhost:27017';

// ---- Errors: every failure becomes {"error": {"code", "message"}} ----
class ApiError extends Error {
  constructor(status, code, message) {
    super(message);
    this.status = status;
    this.code = code;
  }
}
const notFound = (id) => new ApiError(404, 'NOT_FOUND', `Note ${id} not found`);
const invalid = (message) => new ApiError(400, 'VALIDATION_ERROR', message);

// ---- Helpers ----
const toNote = (doc) => ({
  id: doc._id.toString(),
  text: doc.text,
  done: doc.done,
  dueDate: doc.dueDate ?? null,
  createdAt: doc.createdAt,
});

// A malformed id is treated as "not found" (same behaviour on every backend).
const parseId = (raw) => (ObjectId.isValid(raw) ? new ObjectId(raw) : null);

// dueDate: omitted/null -> null, otherwise a REAL date "YYYY-MM-DD".
// The round trip through Date catches impossible dates such as 2026-02-30.
function parseDueDate(value) {
  if (value === undefined || value === null) return null;
  const bad = invalid('dueDate must be a date in YYYY-MM-DD format or null');
  if (typeof value !== 'string' || !/^\d{4}-\d{2}-\d{2}$/.test(value)) throw bad;
  const d = new Date(`${value}T00:00:00Z`);
  if (Number.isNaN(d.getTime()) || d.toISOString().slice(0, 10) !== value) throw bad;
  return value;
}

function validate(body) {
  const text = typeof body.text === 'string' ? body.text.trim() : '';
  if (!text) throw invalid('text is required');
  if (text.length > 200) throw invalid('text must be at most 200 characters');
  if (body.done !== undefined && typeof body.done !== 'boolean') {
    throw invalid('done must be a boolean');
  }
  return { text, done: body.done ?? false, dueDate: parseDueDate(body.dueDate) };
}

// Express 4 does not catch errors from async handlers by itself.
const wrap = (fn) => (req, res, next) => fn(req, res, next).catch(next);

async function main() {
  const client = new MongoClient(MONGO_URL);
  await client.connect();
  const notes = client.db('notesdb').collection('notes');

  const app = express();
  app.use(express.json());

  app.get('/api/health', (req, res) =>
    res.json({ status: 'ok', backend: 'Node.js + Express + MongoDB' }));

  app.get('/api/notes', wrap(async (req, res) => {
    const docs = await notes.find().sort({ _id: -1 }).toArray();
    res.json(docs.map(toNote));
  }));

  app.get('/api/notes/:id', wrap(async (req, res) => {
    const _id = parseId(req.params.id);
    const doc = _id && (await notes.findOne({ _id }));
    if (!doc) throw notFound(req.params.id);
    res.json(toNote(doc));
  }));

  app.post('/api/notes', wrap(async (req, res) => {
    const { text, done, dueDate } = validate(req.body);
    const doc = { text, done, dueDate, createdAt: new Date() };
    const result = await notes.insertOne(doc);
    res.status(201).json(toNote({ ...doc, _id: result.insertedId }));
  }));

  app.put('/api/notes/:id', wrap(async (req, res) => {
    const _id = parseId(req.params.id);
    if (!_id) throw notFound(req.params.id);
    const { text, done, dueDate } = validate(req.body);
    const doc = await notes.findOneAndUpdate(
      { _id },
      { $set: { text, done, dueDate } },
      { returnDocument: 'after' },
    );
    if (!doc) throw notFound(req.params.id);
    res.json(toNote(doc));
  }));

  app.delete('/api/notes/:id', wrap(async (req, res) => {
    const _id = parseId(req.params.id);
    const result = _id && (await notes.deleteOne({ _id }));
    if (!result || result.deletedCount === 0) throw notFound(req.params.id);
    res.status(204).end();
  }));

  // Any other /api/... path
  app.use('/api', (req, res, next) => next(notFound(req.path)));

  // Central error handler (must have 4 arguments)
  app.use((err, req, res, next) => {
    if (err.type === 'entity.parse.failed') {
      err = new ApiError(400, 'INVALID_JSON', 'Request body is not valid JSON');
    }
    if (!(err instanceof ApiError)) {
      console.error(err);
      err = new ApiError(500, 'INTERNAL_ERROR', 'Unexpected server error');
    }
    res.status(err.status).json({ error: { code: err.code, message: err.message } });
  });

  app.listen(PORT, () => console.log(`Backend listening on ${PORT}`));
}

main().catch((err) => {
  console.error(err);
  process.exit(1);
});
