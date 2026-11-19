import { useState } from 'react';
import { CircleMarker, MapContainer, Popup, TileLayer } from 'react-leaflet';
import { Link } from 'react-router-dom';
import { api, optional } from '../api.js';
import { PairBars, Donut } from '../charts.jsx';
import { Icon } from '../icons.jsx';
import { SIZE, STATUS, WASTE, bandRows, fcfa, kg, nf, pct, useAsync } from '../lib.js';
import { Card, CardHead, ErrorBox, Kpi, Loading, Pill } from '../ui.jsx';
import { ScheduleDialog } from '../Dialogs.jsx';

export const OUAGA = [12.3714, -1.5197];

export default function Dashboard() {
  const ov = useAsync(() => api.get('/api/public/overview'));
  const latest = useAsync(() => optional(api.get('/api/admin/latest')));
  const prio = useAsync(() => api.get('/api/dumps/priorities'));
  const geo = useAsync(() => api.get('/api/dumps?limit=2000'));
  const cand = useAsync(() => api.get('/api/candidates/stats').catch(() => null));
  const [sched, setSched] = useState(null);

  if (ov.loading && !ov.data) return <Loading />;
  if (ov.error && !ov.data) return <div className="page"><ErrorBox error={ov.error} retry={ov.reload} /></div>;

  const by = ov.data?.by_status || {};
  const count = (k) => by[k]?.count || 0;
  const toDo = count('verified') + count('scheduled');
  const L = latest.data;
  const sim = L?.simulation;
  const sum = sim?.summary;
  const m = L?.plan?.metrics;
  const params = L?.request?.params || {};
  const rate = sum?.collection_rate;
  const leak = sum?.leakage_rate?.mean ?? 0;
  const parts = rate
    ? [
        { name: 'Collectés', value: rate.mean, color: '#47a037' },
        { name: 'Fuites vers les dépotoirs', value: leak, color: '#d64545' },
        { name: 'Restés dans les points', value: Math.max(0, 1 - rate.mean - leak), color: '#cdd7e1' },
      ]
    : null;
  const collected = bandRows(sim?.series, 'collected_kg', 0.001);
  const wild = bandRows(sim?.series, 'wild_kg', 0.001);
  const bars = collected.map((c, i) => ({ day: c.day, collected: c.mean, wild: wild[i]?.mean ?? 0 }));
  const features = geo.data?.features || [];
  const top = (prio.data?.items || []).slice(0, 5);

  return (
    <div className="page">
      <div className="grid g4">
        <Kpi
          hero
          label="Taux de collecte global"
          icon={<Icon name="pulse" />}
          value={rate ? pct(rate.mean, 1) : '—'}
          foot={
            rate ? (
              <span>
                Fourchette {pct(rate.p05)} – {pct(rate.p95)} sur {sim.horizon_days} jours
              </span>
            ) : (
              <Link to="/parametres" style={{ textDecoration: 'underline' }}>
                Aucun plan calculé. Lancer un calcul
              </Link>
            )
          }
        />
        <Kpi
          label="Dépotoirs à traiter"
          icon={<Icon name="shield" />}
          value={nf(toDo)}
          foot={
            <>
              <Pill tone="green">{nf(ov.data.cleaned_last_30_days)} nettoyés en 30 j</Pill>
              <span>{count('pending')} en attente de vérification</span>
            </>
          }
        />
        <Kpi
          label="Flotte du dernier plan"
          icon={<Icon name="truck" />}
          value={params.trucks != null ? `${params.trucks} camions` : '—'}
          foot={
            <>
              {params.tricycles ? <Pill>{params.tricycles} tricycles</Pill> : null}
              {(L?.plan?.applied_events || []).map((e) => (
                <Pill key={String(e)} tone="red">
                  {String(e)}
                </Pill>
              ))}
              {params.trucks == null ? <span>Aucun plan calculé</span> : null}
            </>
          }
        />
        <Kpi
          label="Coût mensuel estimé"
          icon={<Icon name="euro" />}
          value={m ? fcfa(m.cost_per_month) : '—'}
          foot={m ? <Pill tone={m.within_budget ? 'green' : 'red'}>{m.within_budget ? 'Budget respecté' : 'Budget dépassé'}</Pill> : <span>Aucun plan calculé</span>}
        />
      </div>

      <div className="grid g-main" style={{ marginTop: 18 }}>
        <Card>
          <CardHead title="Collecte et fuites par jour" sub="Tonnes par jour, moyenne des réplications de la simulation" />
          {bars.length ? (
            <PairBars rows={bars} a={{ key: 'collected', name: 'Collecté', color: '#47a037' }} b={{ key: 'wild', name: 'Fuites vers les dépotoirs', color: '#d64545' }} unit="t" />
          ) : (
            <div className="muted">Calculez un plan pour voir la courbe.</div>
          )}
        </Card>
        <Card>
          <CardHead title="Devenir des déchets" sub="Part des déchets produits, sur l’horizon simulé" />
          {parts ? <Donut parts={parts} center={pct(rate.mean)} sub="collectés" /> : <div className="muted">Aucune simulation disponible.</div>}
          {sum ? (
            <div className="grid g3" style={{ marginTop: 10, gap: 8 }}>
              <div className="card" style={{ padding: 12 }}>
                <div className="muted small">Dépotoirs actifs</div>
                <b>{nf(sum.active_dumps?.mean, 1)}</b>
              </div>
              <div className="card" style={{ padding: 12 }}>
                <div className="muted small">Brigade Laabal</div>
                <b>{kg(sum.cleaned_by_laabal_kg?.mean)}</b>
              </div>
              <div className="card" style={{ padding: 12 }}>
                <div className="muted small">Valorisés</div>
                <b>{kg(sum.diverted_kg?.mean)}</b>
              </div>
            </div>
          ) : null}
        </Card>
      </div>

      <div className="grid g-main" style={{ marginTop: 18 }}>
        <Card>
          <CardHead title="Carte ouverte et zones critiques" sub={`${features.length} dépotoir(s) suivis`} right={<Link className="btn sm" to="/carte">Ouvrir la carte</Link>} />
          <div className="map-box">
            <MapContainer center={OUAGA} zoom={11} style={{ height: 360 }} scrollWheelZoom={false}>
              <TileLayer attribution="© contributeurs OpenStreetMap" url="https://tile.openstreetmap.org/{z}/{x}/{y}.png" />
              {features.map((f) => {
                const [lon, lat] = f.geometry.coordinates;
                const s = STATUS[f.properties.status] || STATUS.pending;
                return (
                  <CircleMarker key={f.properties.id} center={[lat, lon]} radius={f.properties.size === 'large' ? 9 : 6} pathOptions={{ color: '#fff', weight: 1.5, fillColor: s.color, fillOpacity: 0.92 }}>
                    <Popup>
                      <b>{s.label}</b>
                      <br />
                      {SIZE[f.properties.size]} · {WASTE[f.properties.waste_type]} · {kg(f.properties.est_kg)}
                    </Popup>
                  </CircleMarker>
                );
              })}
            </MapContainer>
          </div>
        </Card>
        <Card>
          <CardHead title="Priorités sanitaires" sub="Dépotoirs confirmés les plus urgents" />
          {prio.loading && !prio.data ? <Loading /> : null}
          {!top.length && !prio.loading ? <div className="muted">Aucun dépotoir confirmé pour le moment.</div> : null}
          <div className="stack">
            {top.map((d) => (
              <div key={d.id} className="row" style={{ padding: 12, border: '1px solid var(--line)', borderRadius: 14 }}>
                <div style={{ width: 44, height: 44, borderRadius: 12, background: '#fbe6e6', color: '#b83a3a', display: 'grid', placeItems: 'center', fontWeight: 800 }}>{Math.round(d.priority_score)}</div>
                <div className="sp">
                  <div style={{ fontWeight: 700 }}>
                    {SIZE[d.size]} · {WASTE[d.waste_type]}
                  </div>
                  <div className="muted small">
                    {kg(d.est_kg)} · {d.main_driver || 'priorité calculée'}
                  </div>
                </div>
                {d.status === 'verified' ? (
                  <button className="btn sm primary" onClick={() => setSched(d)}>
                    Programmer
                  </button>
                ) : (
                  <Pill tone="blue">Programmé</Pill>
                )}
              </div>
            ))}
          </div>
          {cand.data ? (
            <div className="note" style={{ marginTop: 14 }}>
              Détection satellite : {cand.data.precision != null ? `précision ${pct(cand.data.precision)} sur ${cand.data.reviewed} vérifiés` : 'aucune vérification terrain pour le moment'}.
            </div>
          ) : null}
        </Card>
      </div>
      {sched ? (
        <ScheduleDialog
          dump={sched}
          onClose={() => setSched(null)}
          onDone={() => {
            setSched(null);
            prio.reload();
            geo.reload();
            ov.reload();
          }}
        />
      ) : null}
    </div>
  );
}
