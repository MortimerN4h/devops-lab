// Runs once, when the mongo-data volume is empty (see docker-compose.yml).
db = db.getSiblingDB('notesdb');

// dueDate is a plain "YYYY-MM-DD" string, relative to the day the seed runs.
const day = (offset) => new Date(Date.now() + offset * 86400000).toISOString().slice(0, 10);

db.notes.insertMany([
  { text: 'Learn Docker', done: true, dueDate: day(-2), createdAt: new Date() },
  { text: 'Learn Terraform', done: false, dueDate: day(0), createdAt: new Date() },
  { text: 'Deploy to AWS', done: false, dueDate: day(7), createdAt: new Date() },
  { text: 'Read the Nginx docs', done: false, dueDate: null, createdAt: new Date() }
]);
