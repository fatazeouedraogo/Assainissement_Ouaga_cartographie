import { useEffect, useRef, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, optional } from '../api.js';
import { Icon } from '../icons.jsx';
import { EVENTS, ago, eventPayload, fcfa, kg, nf, pct, useAsync } from '../lib.js';
import { Card, CardHead, ErrorBox, Kpi, Loading, Modal, Pill, Slider, Switch, useToast } from '../ui.jsx';

const INDICATORS = [
  ['collection_rate', 'Taux de collecte', pct, true],
  ['leakage_rate', 'Fuites vers les dépotoirs', pct, false],
  ['active_dumps', 'Dépotoirs actifs', (v) => nf(v, 1), false],
  ['dump_stock_kg', 'Stock dans les dépotoirs', kg, false],
  ['cost_per_month', 'Coût mensuel', fcfa, false],
  ['equity_index', 'Indice d’équité', (v) => nf(v, 2), true],
  ['exposed_people', 'Population exposée', nf, false],
  ['km_per_day', 'Kilomètres par jour', (v) => nf(v, 0), false],
];
const val = (x) => (x && typeof x === 'object' ? x.mean : x);
const avg = (a) => (a && a.length ? a.reduce((s, v) => s + v, 0) / a.length : null);

export default function Params() {
  const toast = useToast();
  const controls = useAsync(() => api.get('/api/plan/controls'));
  const latest = useAsync(() => optional(api.get('/api/admin/latest')));
  const saved = useAsync(() => api.get('/api/scenarios').catch(() => null));
  const [vals, setVals] = useState({});
  const [ev, setEv] = useState({});
  const [res, setRes] = useState(null);
  const [running, setRunning] = useState(false);
  const [cmp, setCmp] = useState(null);
  const [cmpBusy, setCmpBusy] = useState(false);
  const [history, setHistory] = useState(null);
  const [saveOpen, setSaveOpen] = useState(false);
  const [name, setName] = useState('');
  const init = useRef(false);

  const list = controls.data ? controls.data.controls || controls.data : [];
  const savedList = (() => {
    const d = saved.data;
    return Array.isArray(d) ? d : d?.scenarios || d?.items || [];
  })();

  function apply(request) {
    const base = Object.fromEntries(list.map((c) => [c.key, c.default]));
    const p = request?.params || {};
    setVals({ ...base, ...Object.fromEntries(Object.entries(p).filter(([k]) => k in base)) });
    const e = {};
    (request?.events || []).forEach((x) => {
      if (EVENTS[x.kind]) e[x.kind] = { on: true, value: x.value ?? EVENTS[x.kind].value };
    });
    setEv(e);
  }

  useEffect(() => {
    if (init.current || !list.length || latest.loading) return;
    init.current = true;
    apply(latest.data?.request);
    setRes(latest.data || null);
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, [list, latest.loading, latest.data]);

  const events = () =>
    Object.entries(ev)
      .filter(([, v]) => v.on)
      .map(([k, v]) => eventPayload(k, v.value));

  async function run() {
    setRunning(true);
    try {
      const j = await api.post('/api/plan', { params: vals, events: events(), simulate: true, time_limit_s: 8 });
      setRes(j);
      toast('Plan recalculé', 'ok');
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      setRunning(false);
    }
  }

  async function compare() {
    setCmpBusy(true);
    try {
      const j = await api.post('/api/scenarios/compare', {
        inline: [
          { name: 'A · Réglages d’origine du moteur', params: {}, events: [] },
          { name: 'B · Réglages et aléas actuels', params: vals, events: events() },
        ],
        base_params: {},
      });
      setCmp(j);
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      setCmpBusy(false);
    }
  }

  async function saveScenario() {
    try {
      await api.post('/api/scenarios', { name: name.trim(), params: vals, events: events() });
      toast('Scénario enregistré', 'ok');
      setSaveOpen(false);
      setName('');
      saved.reload();
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  async function openHistory() {
    try {
      setHistory((await api.get('/api/admin/runs')).items);
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  async function loadRun(id) {
    try {
      const j = await api.get(`/api/admin/runs/${id}`);
      apply(j.request);
      setRes(j);
      setHistory(null);
      toast('Calcul rechargé', 'ok');
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  if ((controls.loading && !controls.data) || latest.loading) return <Loading />;
  if (controls.error && !controls.data) return <div className="page"><ErrorBox error={controls.error} retry={controls.reload} /></div>;

  const groups = {};
  list.forEach((c) => (groups[c.group || 'Réglages'] ||= []).push(c));
  const plan = res?.plan;
  const m = plan?.metrics;
  const series = res?.simulation?.series;
  const collected = avg(series?.collected_kg?.mean);
  const wild = avg(series?.wild_kg?.mean);
  const total = (collected || 0) + (wild || 0);
  const scenarios = cmp?.scenarios || [];

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h2>Paramètres et aléas</h2>
          <p>Réglez les moyens de la commune, injectez des imprévus et recalculez le plan avec le moteur. Chaque calcul est enregistré dans l’historique.</p>
        </div>
        <div className="row wrap">
          <button className="btn" onClick={openHistory}>
            <Icon name="history" size={18} /> Historique des calculs
          </button>
          {savedList.length ? (
            <select
              style={{ padding: 10, borderRadius: 12, border: '1px solid var(--line)' }}
              defaultValue=""
              onChange={(e) => {
                const s = savedList.find((x) => String(x.id) === e.target.value);
                if (s) apply({ params: s.params, events: s.events });
                e.target.value = '';
              }}
            >
              <option value="">Charger un scénario…</option>
              {savedList.map((s) => (
                <option key={s.id} value={s.id}>
                  {s.name}
                </option>
              ))}
            </select>
          ) : null}
          <button className="btn primary" disabled={running} onClick={run}>
            <Icon name="refresh" size={18} /> {running ? 'Calcul…' : 'Recalculer le plan'}
          </button>
        </div>
      </div>

      <div className="grid g2">
        <div className="stack">
          {Object.entries(groups).map(([g, cs]) => (
            <Card key={g}>
              <CardHead title={g} />
              {cs.map((c) => (
                <Slider key={c.key} label={c.label} min={c.min} max={c.max} step={c.step || 1} unit={c.unit} value={vals[c.key] ?? c.default} onChange={(v) => setVals((s) => ({ ...s, [c.key]: v }))} />
              ))}
            </Card>
          ))}
        </div>

        <div className="stack">
          <Card>
            <CardHead title="Panneau d’épreuve en direct" sub="Imprévus injectés dans le calcul" right={<Pill tone={events().length ? 'red' : ''}>{events().length} aléa(s) actif(s)</Pill>} />
            <div className="stack">
              {Object.entries(EVENTS).map(([k, d]) => {
                const cur = ev[k] || { on: false, value: d.value };
                return (
                  <div key={k} className={`alea ${cur.on ? 'on' : ''}`}>
                    <div className="sp">
                      <div className="t">{d.label}</div>
                      <div className="muted small">{d.hint}</div>
                    </div>
                    {d.value != null ? (
                      <input
                        type="number"
                        min={d.percent ? d.min * 100 : d.min}
                        max={d.percent ? d.max * 100 : d.max}
                        step={d.percent ? d.step * 100 : d.step}
                        value={d.percent ? Math.round((cur.value ?? d.value) * 100) : cur.value ?? d.value}
                        onChange={(e) => setEv((s) => ({ ...s, [k]: { ...cur, value: d.percent ? Number(e.target.value) / 100 : Number(e.target.value) } }))}
                      />
                    ) : null}
                    {d.unit ? <span className="muted small">{d.unit}</span> : null}
                    <Switch checked={cur.on} onChange={(on) => setEv((s) => ({ ...s, [k]: { ...cur, on } }))} />
                  </div>
                );
              })}
            </div>
          </Card>

          <Card>
            <CardHead title="Résultat du dernier calcul" sub={res?.created_at ? `Enregistré ${ago(res.created_at)}` : 'Lancez un calcul pour voir le résultat'} right={m ? <Pill tone={m.within_budget ? 'green' : 'red'}>{m.within_budget ? 'Dans le budget' : 'Hors budget'}</Pill> : null} />
            {!m ? <div className="muted">Aucun résultat pour l’instant.</div> : null}
            {m ? (
              <>
                <div className="grid g2" style={{ gap: 12 }}>
                  <Kpi label="Couverture à pied" value={pct(m.coverage)} />
                  <Kpi label="Indice d’équité" value={nf(m.equity_index, 2)} />
                  <Kpi label="Coût mensuel" value={fcfa(m.cost_per_month)} />
                  <Kpi label="Kilomètres par jour" value={`${nf(m.km_per_day)} km`} />
                </div>
                {total > 0 ? (
                  <div style={{ marginTop: 16 }}>
                    <b>Bilan massique journalier</b>
                    <div className="bar" style={{ margin: '8px 0' }}>
                      <i style={{ width: `${(100 * collected) / total}%`, background: '#47a037' }} />
                      <i style={{ width: `${(100 * wild) / total}%`, background: '#d64545' }} />
                    </div>
                    <div className="row small muted">
                      <span style={{ color: '#2c7a2f' }}>● collecté {kg(collected)}/j</span>
                      <span className="sp" />
                      <span style={{ color: '#b83a3a' }}>● fuites {kg(wild)}/j</span>
                    </div>
                  </div>
                ) : null}
                {(res?.warnings || []).map((w, i) => (
                  <div key={i} className="note" style={{ marginTop: 10, background: '#e1eef8', color: '#214472' }}>
                    {String(w)}
                  </div>
                ))}
              </>
            ) : null}
          </Card>
        </div>
      </div>

      <Card style={{ marginTop: 18 }}>
        <CardHead
          title="Comparateur stratégique"
          sub="Réglages d’origine du moteur contre les réglages et aléas actuels, simulés tous les deux"
          right={
            <div className="row">
              <button className="btn" onClick={() => setSaveOpen(true)}>
                Enregistrer ce scénario
              </button>
              <button className="btn primary" disabled={cmpBusy} onClick={compare}>
                {cmpBusy ? 'Comparaison…' : 'Comparer'}
              </button>
            </div>
          }
        />
        {!scenarios.length ? <div className="muted">Touchez « Comparer » pour lancer les deux simulations.</div> : null}
        {scenarios.length ? (
          <div className="table-wrap">
            <table className="table">
              <thead>
                <tr>
                  <th>Indicateur</th>
                  {scenarios.map((s, i) => (
                    <th key={i}>{s.name}</th>
                  ))}
                  <th>Écart B − A</th>
                </tr>
              </thead>
              <tbody>
                {INDICATORS.map(([k, label, f, higherBetter]) => {
                  const hs = scenarios.map((s) => val((s.headline || s.summary || {})[k]));
                  if (hs.every((x) => x == null)) return null;
                  const d = hs.length > 1 && hs[0] != null && hs[1] != null ? hs[1] - hs[0] : null;
                  const good = d == null || d === 0 ? null : higherBetter ? d > 0 : d < 0;
                  return (
                    <tr key={k}>
                      <td>{label}</td>
                      {hs.map((x, i) => (
                        <td key={i} className={i === 1 ? 'best mono' : 'mono'}>
                          {x == null ? '—' : f(x)}
                        </td>
                      ))}
                      <td>{d == null ? '—' : <Pill tone={good == null ? '' : good ? 'green' : 'red'}>{d > 0 ? '+' : ''}{f(d)}</Pill>}</td>
                    </tr>
                  );
                })}
              </tbody>
            </table>
          </div>
        ) : null}
        <div style={{ marginTop: 14 }}>
          <Link className="btn sm" to="/simulation">
            Voir la simulation détaillée
          </Link>
        </div>
      </Card>

      {history ? (
        <Modal title="Historique des calculs" onClose={() => setHistory(null)}>
          <div className="stack">
            {!history.length ? <div className="muted">Aucun calcul enregistré.</div> : null}
            {history.map((h) => (
              <button key={h.id} className="btn" style={{ justifyContent: 'space-between' }} onClick={() => loadRun(h.id)}>
                <span>{new Date(h.created_at).toLocaleString('fr-FR')}</span>
                <span className="muted small">{(h.request?.events || []).length} aléa(s)</span>
              </button>
            ))}
          </div>
        </Modal>
      ) : null}
      {saveOpen ? (
        <Modal title="Enregistrer le scénario" onClose={() => setSaveOpen(false)}>
          <div className="stack">
            <div className="field">
              <label>Nom du scénario</label>
              <input value={name} onChange={(e) => setName(e.target.value)} placeholder="Saison des pluies, 2 camions en plus" maxLength={80} autoFocus />
            </div>
            <button className="btn primary" disabled={name.trim().length < 2} onClick={saveScenario}>
              Enregistrer
            </button>
          </div>
        </Modal>
      ) : null}
    </div>
  );
}
