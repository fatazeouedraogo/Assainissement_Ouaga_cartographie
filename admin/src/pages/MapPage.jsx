import { useMemo, useState } from 'react';
import { CircleMarker, MapContainer, Polyline, Popup, TileLayer } from 'react-leaflet';
import { api, optional } from '../api.js';
import { SIZE, STATUS, WASTE, kg, useAsync } from '../lib.js';
import { Card, CardHead, ErrorBox, Loading, Pill, Seg, Switch } from '../ui.jsx';
import { ScheduleDialog } from '../Dialogs.jsx';
import { OUAGA } from './Dashboard.jsx';

const COLORS = ['#33a1de', '#47a037', '#214472', '#2c7a2f'];

export default function MapPage() {
  const geo = useAsync(() => api.get('/api/dumps?limit=2000'));
  const latest = useAsync(() => optional(api.get('/api/admin/latest')));
  const [filter, setFilter] = useState('todo');
  const [routes, setRoutes] = useState(true);
  const [sched, setSched] = useState(null);

  const features = geo.data?.features || [];
  const shown = features.filter((f) => {
    const s = f.properties.status;
    if (filter === 'todo') return s === 'verified' || s === 'scheduled';
    if (filter === 'all') return s !== 'rejected';
    return s === filter;
  });

  const lines = useMemo(() => {
    const plan = latest.data?.plan;
    if (!plan?.points || !plan?.groups) return [];
    const pts = Object.fromEntries(plan.points.map((p) => [p.id, [p.lat, p.lon]]));
    const out = [];
    let n = 0;
    for (const g of plan.groups) {
      for (const r of g.routes || []) {
        const path = (r.stops || []).map((s) => pts[s]).filter(Boolean);
        if (path.length > 1) out.push({ path, color: COLORS[n % COLORS.length], kind: r.kind, stops: path.length, n: n + 1 });
        n += 1;
      }
    }
    return out;
  }, [latest.data]);

  if (geo.loading && !geo.data) return <Loading />;
  if (geo.error && !geo.data) return <div className="page"><ErrorBox error={geo.error} retry={geo.reload} /></div>;

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h2>Carte et tournées</h2>
          <p>Les dépotoirs suivis par l’API et les tournées du dernier plan calculé par le moteur.</p>
        </div>
        <div className="row wrap">
          <Seg
            value={filter}
            onChange={setFilter}
            options={[
              ['todo', 'À traiter'],
              ['pending', 'En attente'],
              ['cleaned', 'Nettoyés'],
              ['all', 'Tous'],
            ]}
          />
          <label className="row" style={{ gap: 8 }}>
            <Switch checked={routes} onChange={setRoutes} /> <span>Tournées</span>
          </label>
        </div>
      </div>
      <div className="grid g-main">
        <div className="map-box">
          <MapContainer center={OUAGA} zoom={12} style={{ height: 640 }}>
            <TileLayer attribution="© contributeurs OpenStreetMap" url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" />
            {routes ? lines.map((l) => <Polyline key={l.n} positions={l.path} pathOptions={{ color: l.color, weight: 4, opacity: 0.8 }} />) : null}
            {shown.map((f) => {
              const p = f.properties;
              const [lon, lat] = f.geometry.coordinates;
              const s = STATUS[p.status] || STATUS.pending;
              return (
                <CircleMarker key={p.id} center={[lat, lon]} radius={p.size === 'large' ? 10 : 7} pathOptions={{ color: '#fff', weight: 2, fillColor: s.color, fillOpacity: 0.95 }}>
                  <Popup>
                    <b>{s.label}</b>
                    <br />
                    {SIZE[p.size]} · {WASTE[p.waste_type]} · {kg(p.est_kg)}
                    <br />
                    {p.priority_score ? `Priorité ${Math.round(p.priority_score)}` : null}
                    {p.status === 'verified' ? (
                      <div style={{ marginTop: 8 }}>
                        <button className="btn sm primary" onClick={() => setSched(p)}>
                          Programmer un passage
                        </button>
                      </div>
                    ) : null}
                  </Popup>
                </CircleMarker>
              );
            })}
          </MapContainer>
        </div>
        <Card>
          <CardHead title="Tournées du dernier plan" sub={latest.data ? `Calculé le ${new Date(latest.data.created_at).toLocaleString('fr-FR')}` : 'Aucun plan calculé'} />
          {!lines.length ? <div className="muted">Calculez un plan dans « Paramètres & aléas » pour afficher les tournées.</div> : null}
          <div className="stack">
            {lines.map((l) => (
              <div key={l.n} className="row" style={{ padding: 12, border: '1px solid var(--line)', borderRadius: 14 }}>
                <span className="dot" style={{ background: l.color, width: 14, height: 14 }} />
                <div className="sp">
                  <b>Tournée {String(l.n).padStart(2, '0')}</b>
                  <div className="muted small">{l.stops} arrêts</div>
                </div>
                <Pill tone={l.kind === 'tricycle' ? 'amber' : 'blue'}>{l.kind === 'tricycle' ? 'Tricycle' : 'Camion'}</Pill>
              </div>
            ))}
          </div>
          <div className="muted small" style={{ marginTop: 14 }}>
            {shown.length} dépotoir(s) affiché(s) sur {features.length}.
          </div>
        </Card>
      </div>
      {sched ? (
        <ScheduleDialog
          dump={sched}
          onClose={() => setSched(null)}
          onDone={() => {
            setSched(null);
            geo.reload();
          }}
        />
      ) : null}
    </div>
  );
}
