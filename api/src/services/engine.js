import { config } from '../config.js';
import { AppError } from '../middleware/errors.js';

async function call(path, { method = 'POST', json, form, timeoutMs = 120000 } = {}) {
  const headers = {};
  if (config.engineKey) headers['X-Engine-Key'] = config.engineKey;
  let body;
  if (form) body = form;
  else if (json !== undefined) {
    headers['Content-Type'] = 'application/json';
    body = JSON.stringify(json);
  }
  const ctrl = new AbortController();
  const timer = setTimeout(() => ctrl.abort(), timeoutMs);
  try {
    const res = await fetch(`${config.engineUrl}${path}`, { method, headers, body, signal: ctrl.signal });
    const text = await res.text();
    const data = text ? JSON.parse(text) : null;
    if (!res.ok) throw new AppError(502, 'moteur_erreur', 'Le moteur de calcul a refusé la requête', data);
    return data;
  } catch (e) {
    if (e instanceof AppError) throw e;
    throw new AppError(503, 'moteur_indisponible', 'Le moteur de calcul est injoignable');
  } finally {
    clearTimeout(timer);
  }
}

export const engine = {
  controls: () => call('/v1/controls', { method: 'GET', timeoutMs: 5000 }),
  plan: (json) => call('/v1/plan', { json }),
  simulate: (json) => call('/v1/simulate', { json }),
  compare: (json) => call('/v1/scenarios/compare', { json }),
  sensitivity: (json) => call('/v1/sensitivity', { json }),
  assistant: (json) => call('/v1/assistant/parse', { json, timeoutMs: 8000 }),
  risk: (json) => call('/v1/predict/risk', { json, timeoutMs: 30000 }),
  pareto: (json) => call('/v1/pareto', { json }),
  recommend: (json) => call('/v1/recommend', { json }),
  calibrate: (json) => call('/v1/calibrate', { json }),
  async candidates(buffer, mime, bbox, opts = {}) {
    const form = new FormData();
    form.append('file', new Blob([buffer], { type: mime || 'image/png' }), 'tile.png');
    for (const [k, v] of Object.entries(bbox)) form.append(k, String(v));
    form.append('top', String(opts.top ?? 40));
    for (const k of ['min_score', 'merge_m', 'risk_weight']) if (opts[k] != null) form.append(k, String(opts[k]));
    if (opts.masks) form.append('masks', JSON.stringify(opts.masks));
    if (opts.riskCells?.length) form.append('risk_cells', JSON.stringify(opts.riskCells));
    return call('/v1/satellite/candidates', { form, timeoutMs: 90000 });
  },
  satelliteEvaluate: (json) => call('/v1/satellite/evaluate', { json, timeoutMs: 30000 }),
  priority: (json) => call('/v1/priority/score', { json, timeoutMs: 20000 }),
  async analyzePhoto(buffer, mime) {
    const form = new FormData();
    form.append('file', new Blob([buffer], { type: mime || 'image/jpeg' }), 'photo.jpg');
    try {
      return await call('/v1/photo/analyze', { form, timeoutMs: 8000 });
    } catch {
      return null;
    }
  },
};
