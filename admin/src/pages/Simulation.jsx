import { useEffect, useState } from 'react';
import { Link } from 'react-router-dom';
import { api, download, optional } from '../api.js';
import { BandChart, PairBars } from '../charts.jsx';
import { Icon } from '../icons.jsx';
import { bandRows, fcfa, kg, nf, pct, useAsync } from '../lib.js';
import { Card, CardHead, Empty, ErrorBox, Kpi, Loading, Pill, Seg, useToast } from '../ui.jsx';

export default function Simulation() {
  const toast = useToast();
  const latest = useAsync(() => optional(api.get('/api/admin/latest')));
  const [day, setDay] = useState(1);
  const [playing, setPlaying] = useState(false);
  const [speed, setSpeed] = useState(5);
  const [busy, setBusy] = useState(false);

  const sim = latest.data?.simulation;
  const horizon = sim?.horizon_days || 30;

  useEffect(() => {
    if (!playing) return undefined;
    const t = setInterval(() => {
      setDay((d) => {
        if (d >= horizon) {
          setPlaying(false);
          return horizon;
        }
        return d + 1;
      });
    }, 1000 / speed);
    return () => clearInterval(t);
  }, [playing, speed, horizon]);

  async function rerun() {
    setBusy(true);
    try {
      const r = latest.data.request || {};
      await api.post('/api/plan', { params: r.params || {}, events: r.events || [], simulate: true, time_limit_s: 8 });
      latest.reload();
      toast('Simulation relancée', 'ok');
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      setBusy(false);
    }
  }

  if (latest.loading && !latest.data) return <Loading />;
  if (latest.error && !latest.data) return <div className="page"><ErrorBox error={latest.error} retry={latest.reload} /></div>;
  if (!sim) {
    return (
      <div className="page">
        <Card>
          <Empty title="Aucune simulation disponible" action={<Link className="btn primary" to="/parametres">Calculer un plan</Link>}>
            Lancez un calcul dans « Paramètres et aléas » pour voir la dynamique sur 30 jours.
          </Empty>
        </Card>
      </div>
    );
  }

  const s = sim.summary || {};
  const stock = bandRows(sim.series, 'dump_stock_kg', 0.001);
  const active = bandRows(sim.series, 'active_dumps');
  const col = bandRows(sim.series, 'collected_kg', 0.001);
  const wild = bandRows(sim.series, 'wild_kg', 0.001);
  const bars = col.map((c, i) => ({ day: c.day, collected: c.mean, wild: wild[i]?.mean ?? 0 }));
  const params = latest.data.request?.params || {};
  const events = latest.data.request?.events || [];

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h2>Simulation multi-agents sur {horizon} jours</h2>
          <p>
            {sim.replications ? `${sim.replications} réplications` : 'Plusieurs réplications'} : ménages, pré-collecteurs, brigade Laabal et camions de la mairie. Les courbes montrent la moyenne et la fourchette de 5 à 95 %.
          </p>
        </div>
        <div className="row wrap">
          <button className="btn" disabled={busy} onClick={rerun}>
            <Icon name="refresh" size={18} /> {busy ? 'Calcul…' : 'Relancer'}
          </button>
          <button className="btn dark" onClick={() => download('/api/insights/report.pdf', 'note-de-decision.pdf', { method: 'POST', body: {} }).catch((e) => toast(e.message, 'error'))}>
            <Icon name="download" size={18} /> Note de décision (PDF)
          </button>
        </div>
      </div>

      <Card>
        <div className="row wrap">
          <button className="btn primary" onClick={() => { if (day >= horizon) setDay(1); setPlaying(!playing); }}>
            <Icon name="play" size={16} /> {playing ? 'Pause' : 'Lancer la lecture'}
          </button>
          <Seg value={speed} onChange={setSpeed} options={[[1, '1×'], [5, '5×'], [20, '20×']]} />
          <input type="range" min="1" max={horizon} value={day} onChange={(e) => { setPlaying(false); setDay(Number(e.target.value)); }} style={{ flex: 1, minWidth: 180, accentColor: '#47a037' }} />
          <Pill tone="green">Jour {day} / {horizon}</Pill>
        </div>
        <div className="row wrap" style={{ marginTop: 12 }}>
          {events.length ? events.map((e, i) => <Pill key={i} tone="red">{e.kind}{e.value != null ? ` ${e.value}` : ''}</Pill>) : <span className="muted small">Aucun aléa dans ce calcul.</span>}
          {params.trucks != null ? <Pill>{params.trucks} camions</Pill> : null}
          {params.tricycles ? <Pill>{params.tricycles} tricycles</Pill> : null}
        </div>
      </Card>

      <div className="grid g4" style={{ marginTop: 18 }}>
        <Kpi label="Taux de collecte" value={pct(s.collection_rate?.mean, 1)} foot={s.collection_rate ? `${pct(s.collection_rate.p05)} – ${pct(s.collection_rate.p95)}` : ''} hero />
        <Kpi label="Fuites vers les dépotoirs" value={pct(s.leakage_rate?.mean, 1)} foot="part des déchets produits" />
        <Kpi label="Coût mensuel" value={fcfa(s.cost_per_month?.mean ?? s.cost_per_month)} foot="exploitation de la flotte" />
        <Kpi label="Population exposée" value={nf(s.exposed_people?.mean ?? s.exposed_people)} foot="vivant près d’un dépotoir actif" />
      </div>

      <div className="grid g2" style={{ marginTop: 18 }}>
        <Card>
          <CardHead title="Stock de déchets dans les dépotoirs" sub="Tonnes, au fil des jours" />
          <BandChart rows={stock} unit="t" color="#d64545" cursor={day} name="Stock moyen" />
        </Card>
        <Card>
          <CardHead title="Dépotoirs actifs" sub="Nombre de sites, au fil des jours" />
          <BandChart rows={active} color="#33a1de" cursor={day} name="Sites actifs" />
        </Card>
      </div>
      <Card style={{ marginTop: 18 }}>
        <CardHead title="Collecte et fuites par jour" sub={`À la date du jour ${day} : collecté ${nf(col[day - 1]?.mean, 1)} t, fuites ${nf(wild[day - 1]?.mean, 1)} t`} />
        <PairBars rows={bars} a={{ key: 'collected', name: 'Collecté', color: '#47a037' }} b={{ key: 'wild', name: 'Fuites vers les dépotoirs', color: '#d64545' }} unit="t" cursor={day} />
        <div className="row small muted" style={{ marginTop: 8 }}>
          <span>Brigade Laabal : {kg(s.cleaned_by_laabal_kg?.mean)}</span>
          <span>· Valorisés : {kg(s.diverted_kg?.mean)}</span>
          {s.revenue_month?.mean != null ? <span>· Recettes mensuelles : {fcfa(s.revenue_month.mean)}</span> : null}
        </div>
      </Card>
    </div>
  );
}
