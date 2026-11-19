import { useState } from 'react';
import { useOutletContext } from 'react-router-dom';
import { api, saveBlob } from '../api.js';
import { Icon } from '../icons.jsx';
import { SIZE, STATUS, WASTE, ago, hm, kg, nf, pct, reason, useAsync } from '../lib.js';
import { Card, CardHead, Empty, ErrorBox, Kpi, Loading, Pill, Seg, useToast } from '../ui.jsx';
import { RejectDialog } from '../Dialogs.jsx';

export default function Verification() {
  const toast = useToast();
  const { refreshPending } = useOutletContext();
  const q = useAsync(() => api.get('/api/dumps?status=pending&limit=300'));
  const audit = useAsync(() => api.get('/api/admin/audit?limit=30'));
  const cands = useAsync(() => api.get('/api/candidates').catch(() => ({ candidates: [] })));
  const cstats = useAsync(() => api.get('/api/candidates/stats').catch(() => null));
  const ov = useAsync(() => api.get('/api/public/overview'));
  const [tab, setTab] = useState('reports');
  const [sort, setSort] = useState('priority');
  const [reject, setReject] = useState(null);
  const [busy, setBusy] = useState('');
  const [sizes, setSizes] = useState({});

  const items = (q.data?.features || []).map((f) => ({ ...f.properties, lat: f.geometry.coordinates[1], lon: f.geometry.coordinates[0] }));
  items.sort((a, b) => (sort === 'priority' ? (b.priority_score || 0) - (a.priority_score || 0) : (b.reporter_count || 0) - (a.reporter_count || 0)));
  const by = ov.data?.by_status || {};
  const confirmed = (by.verified?.count || 0) + (by.scheduled?.count || 0) + (by.cleaned?.count || 0);
  const st = audit.data?.stats;
  const cs = cstats.data;

  function reloadAll() {
    q.reload();
    ov.reload();
    cands.reload();
    cstats.reload();
    refreshPending();
  }

  async function run(id, fn, ok) {
    setBusy(id);
    try {
      await fn();
      toast(ok, 'ok');
      reloadAll();
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      setBusy('');
    }
  }

  function exportAudit() {
    const payload = { generated_at: new Date().toISOString(), stats: audit.data?.stats, items: audit.data?.items };
    saveBlob(new Blob([JSON.stringify(payload, null, 2)], { type: 'application/json' }), `audit-signalements-${new Date().toISOString().slice(0, 10)}.json`);
  }

  if (q.loading && !q.data) return <Loading />;
  if (q.error && !q.data) return <div className="page"><ErrorBox error={q.error} retry={q.reload} /></div>;

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h2>Vérification et journal anti-pièges</h2>
          <p>Modération humaine des signalements et trace des signalements écartés ou suspects par les contrôles automatiques.</p>
        </div>
        <Seg
          value={tab}
          onChange={setTab}
          options={[
            ['reports', `Signalements (${items.length})`],
            ['sat', `Satellite (${cands.data?.candidates?.length || 0})`],
          ]}
        />
      </div>

      <div className="grid g4">
        <Kpi label="En attente de validation" value={nf(items.length)} foot="signalements à traiter" />
        <Kpi label="Dépotoirs confirmés" value={nf(confirmed)} foot="depuis le début" />
        <Kpi
          label="Signalements écartés"
          value={nf(st?.rejected)}
          foot={st ? <Pill tone="red">{pct(st.total ? st.rejected / st.total : 0)} du total</Pill> : null}
        />
        <Kpi
          label="Précision de la détection satellite"
          value={cs?.precision != null ? pct(cs.precision) : '—'}
          foot={cs ? `${cs.confirmed ?? 0} confirmés sur ${cs.reviewed ?? 0} vérifiés` : 'aucune donnée'}
        />
      </div>

      <div className="grid g-main" style={{ marginTop: 18 }}>
        <Card>
          {tab === 'reports' ? (
            <>
              <CardHead
                title="File de vérification"
                sub="Validation humaine avant injection dans le plan"
                right={<Seg value={sort} onChange={setSort} options={[['priority', 'Priorité'], ['reporters', 'Recoupements']]} />}
              />
              {!items.length ? <Empty title="Rien à vérifier">Tous les signalements ont été traités.</Empty> : null}
              <div className="stack">
                {items.map((d) => (
                  <div className="queue-item" key={d.id}>
                    {d.before_photo ? <img src={api.photo(d.before_photo)} alt="Dépotoir signalé" loading="lazy" /> : <div className="noimg">Pas de photo</div>}
                    <div>
                      <div className="row wrap">
                        <h4 style={{ fontSize: 17 }}>#{d.id.slice(0, 6).toUpperCase()}</h4>
                        <Pill tone={d.size === 'large' ? 'red' : d.size === 'medium' ? 'amber' : ''}>{SIZE[d.size]}</Pill>
                        <Pill>{WASTE[d.waste_type]}</Pill>
                        <span className="sp" />
                        <span className="muted small">{d.priority_score ? `Priorité ${Math.round(d.priority_score)}` : ''}</span>
                      </div>
                      <div className="info-line">
                        <Icon name="map" size={16} /> {d.lat.toFixed(4)}° N, {Math.abs(d.lon).toFixed(4)}° {d.lon < 0 ? 'O' : 'E'}
                      </div>
                      <div className={`info-line ${d.reporter_count > 1 ? 'ok' : 'warn'}`}>
                        {d.reporter_count} signalement(s) · confiance {pct(d.confidence)} · environ {kg(d.est_kg)}
                      </div>
                      <div className="row" style={{ marginTop: 12 }}>
                        <button className="btn danger" disabled={busy === d.id} onClick={() => setReject({ kind: 'dump', id: d.id })}>
                          Rejeter
                        </button>
                        <button className="btn primary sp" disabled={busy === d.id} onClick={() => run(d.id, () => api.post(`/api/dumps/${d.id}/verify`), 'Dépotoir confirmé')}>
                          <Icon name="check" size={18} /> Valider et injecter au plan
                        </button>
                      </div>
                    </div>
                  </div>
                ))}
              </div>
            </>
          ) : (
            <>
              <CardHead title="Candidats détectés par satellite" sub="À confirmer sur le terrain. Chaque réponse améliore la mesure de précision." />
              {!cands.data?.candidates?.length ? <Empty title="Aucun candidat">Lancez une analyse satellite pour en obtenir.</Empty> : null}
              <div className="stack">
                {(cands.data?.candidates || []).map((c) => (
                  <div key={c.id} className="row wrap" style={{ padding: 14, border: '1px solid var(--line)', borderRadius: 14 }}>
                    <div className="sp">
                      <b>Zone suspecte · score {Number(c.score).toFixed(1)}</b>
                      <div className="muted small">
                        {Number(c.lat).toFixed(4)}, {Number(c.lon).toFixed(4)}
                      </div>
                    </div>
                    <select value={sizes[c.id] || 'medium'} onChange={(e) => setSizes({ ...sizes, [c.id]: e.target.value })} style={{ padding: 8, borderRadius: 10, border: '1px solid var(--line)' }}>
                      {Object.entries(SIZE).map(([k, v]) => (
                        <option key={k} value={k}>
                          {v}
                        </option>
                      ))}
                    </select>
                    <button className="btn sm primary" disabled={busy === c.id} onClick={() => run(c.id, () => api.post(`/api/candidates/${c.id}/confirm`, { size: sizes[c.id] || 'medium' }), 'Dépotoir confirmé')}>
                      Confirmer
                    </button>
                    <button className="btn sm danger" onClick={() => setReject({ kind: 'cand', id: c.id })}>
                      Fausse alerte
                    </button>
                  </div>
                ))}
              </div>
            </>
          )}
        </Card>

        <Card>
          <CardHead title="Journal anti-pièges" sub="Signalements écartés ou suspects, par les contrôles automatiques" />
          {st ? (
            <div style={{ marginBottom: 16 }}>
              <div className="row small muted" style={{ marginBottom: 6 }}>
                <span>{nf(st.total)} signalements reçus</span>
                <span className="sp" />
                <span>{nf(st.last_24h)} sur 24 h</span>
              </div>
              <div className="bar">
                <i style={{ width: `${st.total ? (100 * (st.total - st.rejected - st.flagged)) / st.total : 0}%`, background: '#47a037' }} />
                <i style={{ width: `${st.total ? (100 * st.flagged) / st.total : 0}%`, background: '#33a1de' }} />
                <i style={{ width: `${st.total ? (100 * st.rejected) / st.total : 0}%`, background: '#d64545' }} />
              </div>
              <div className="row small muted" style={{ marginTop: 6 }}>
                <span>● acceptés</span>
                <span style={{ color: '#214472' }}>● suspects ({st.flagged})</span>
                <span style={{ color: '#b83a3a' }}>● rejetés ({st.rejected})</span>
              </div>
            </div>
          ) : null}
          {audit.loading && !audit.data ? <Loading /> : null}
          {audit.data && !audit.data.items.length ? <div className="muted">Aucun signalement écarté ou suspect pour le moment.</div> : null}
          <div className="timeline">
            {(audit.data?.items || []).map((a) => {
              const reasons = [...new Set([...(a.reject_reasons || []), ...(a.flags || [])])];
              return (
                <div key={a.id} className={`tl-item ${a.status === 'rejected' ? 'red' : 'amber'}`}>
                  <div className="row">
                    <b>{a.status === 'rejected' ? 'Rejeté' : 'Suspect'}</b>
                    <span className="sp" />
                    <span className="muted small">
                      {hm(a.created_at)} · {ago(a.created_at)}
                    </span>
                  </div>
                  <div className="small" style={{ margin: '4px 0' }}>
                    {a.author} · {SIZE[a.size]} · confiance {pct(a.credibility)}
                  </div>
                  <div className="row wrap">
                    {reasons.map((r) => (
                      <Pill key={r} tone={a.status === 'rejected' ? 'red' : 'amber'}>
                        {reason(r)}
                      </Pill>
                    ))}
                  </div>
                </div>
              );
            })}
          </div>
          <button className="btn dark block" style={{ marginTop: 16 }} onClick={exportAudit} disabled={!audit.data}>
            <Icon name="download" size={18} /> Télécharger le rapport d’audit (JSON)
          </button>
        </Card>
      </div>

      {reject ? (
        <RejectDialog
          title={reject.kind === 'cand' ? 'Pourquoi est-ce une fausse alerte ?' : 'Motif du rejet'}
          onClose={() => setReject(null)}
          onConfirm={(key, label) => {
            const r = reject;
            setReject(null);
            if (r.kind === 'cand') run(r.id, () => api.post(`/api/candidates/${r.id}/dismiss`, { reason: key }), 'Fausse alerte enregistrée');
            else run(r.id, () => api.post(`/api/dumps/${r.id}/reject`, { reason: label }), 'Signalement rejeté');
          }}
        />
      ) : null}
    </div>
  );
}
