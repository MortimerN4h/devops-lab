// All calls go to /api/... on the same origin; nginx forwards them to the backend.
async function request(method, path, body) {
  const res = await fetch(`/api${path}`, {
    method,
    headers: body ? { 'Content-Type': 'application/json' } : undefined,
    body: body ? JSON.stringify(body) : undefined,
  });
  if (res.status === 204) return null; // DELETE: no body
  const data = await res.json().catch(() => null);
  if (!res.ok) throw new Error(data?.error?.message || `HTTP ${res.status}`);
  return data;
}

export const api = {
  health: () => request('GET', '/health'),
  list: () => request('GET', '/notes'),
  create: (note) => request('POST', '/notes', note),
  update: (id, note) => request('PUT', `/notes/${id}`, note),
  remove: (id) => request('DELETE', `/notes/${id}`),
};
