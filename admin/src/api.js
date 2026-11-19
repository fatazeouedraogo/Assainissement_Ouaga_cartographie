const KEY = 'oc_admin_token';
const BASE_KEY = 'oc_admin_api';

export const session = {
  token: () => localStorage.getItem(KEY),
  setToken: (t) => localStorage.setItem(KEY, t),
  clear: () => localStorage.removeItem(KEY),
  base: () => (localStorage.getItem(BASE_KEY) || '').replace(/\/+$/, ''),
  setBase: (b) => (b ? localStorage.setItem(BASE_KEY, b) : localStorage.removeItem(BASE_KEY)),
};

export class ApiError extends Error {
  constructor(status, message) {
    super(message);
    this.status = status;
  }
}

async function request(path, { method = 'GET', body, form, raw } = {}) {
  const headers = { Accept: 'application/json' };
  const t = session.token();
  if (t) headers.Authorization = `Bearer ${t}`;
  if (body !== undefined) headers['Content-Type'] = 'application/json';
  let res;
  try {
    res = await fetch(session.base() + path, { method, headers, body: body !== undefined ? JSON.stringify(body) : form });
  } catch {
    throw new ApiError(0, 'Serveur injoignable. Vérifiez que l’API tourne.');
  }
  if (raw) {
    if (!res.ok) throw new ApiError(res.status, `Erreur ${res.status}`);
    return res;
  }
  const text = await res.text();
  let data = null;
  try {
    data = text ? JSON.parse(text) : null;
  } catch {
    data = null;
  }
  if (!res.ok) {
    if (res.status === 401) {
      session.clear();
      window.dispatchEvent(new Event('oc-auth'));
    }
    const e = data && data.error;
    throw new ApiError(res.status, (e && e.message) || (data && data.message) || (typeof e === 'string' ? e : `Erreur ${res.status}`));
  }
  return data;
}

export const api = {
  get: (p) => request(p),
  post: (p, b) => request(p, { method: 'POST', body: b ?? {} }),
  put: (p, b) => request(p, { method: 'PUT', body: b }),
  del: (p) => request(p, { method: 'DELETE' }),
  raw: (p, opts) => request(p, { ...opts, raw: true }),
  photo: (name) => (name ? (name.startsWith('http') ? name : `${session.base()}/uploads/${name}`) : null),
};

export const optional = (promise) => promise.catch((e) => (e.status === 404 ? null : Promise.reject(e)));

export async function download(path, filename, opts) {
  const res = await api.raw(path, opts);
  const blob = await res.blob();
  saveBlob(blob, filename);
}

export function saveBlob(blob, filename) {
  const url = URL.createObjectURL(blob);
  const a = document.createElement('a');
  a.href = url;
  a.download = filename;
  document.body.appendChild(a);
  a.click();
  a.remove();
  URL.revokeObjectURL(url);
}
