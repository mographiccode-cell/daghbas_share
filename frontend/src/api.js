const BASE = import.meta.env.VITE_API_URL || 'http://127.0.0.1:8000'

export async function api(path, { method = 'GET', token, body } = {}) {
  const headers = { 'Content-Type': 'application/json' }
  if (token) headers.Authorization = `Bearer ${token}`
  const res = await fetch(`${BASE}${path}`, { method, headers, body: body === undefined ? undefined : JSON.stringify(body) })
  let data = null
  try { data = await res.json() } catch { data = {} }
  if (!res.ok) throw new Error(data?.detail || `HTTP ${res.status}`)
  return data
}
