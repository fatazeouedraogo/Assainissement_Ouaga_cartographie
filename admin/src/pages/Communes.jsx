import { useEffect, useRef, useState } from 'react';
import { api, saveBlob } from '../api.js';
import { useAuth } from '../App.jsx';
import { Icon } from '../icons.jsx';
import { nf, useAsync } from '../lib.js';
import { Card, CardHead, ErrorBox, Loading, Pill, useToast } from '../ui.jsx';

const blank = { slug: '', name: '', region: '', lat: 12.3714, lon: -1.5197, radius_km: 15, population: '', trucks: '', fuel_price_fcfa: '', depot: null, landfill: null };

const slugify = (s) => s.toLowerCase().normalize('NFD').replace(/[\u0300-\u036f]/g, '').replace(/[^a-z0-9]+/g, '-').replace(/^-+|-+$/g, '').slice(0, 40);
const numOrNull = (v) => (v === '' || v == null || Number.isNaN(Number(v)) ? null : Number(v));

function toConfig(c) {
  return {
    schema_version: '1.0',
    licence: 'Open Database License (ODbL) 1.0',
    municipality: c.name,
    region: c.region || undefined,
    country: 'Burkina Faso',
    crs: 'EPSG:4326',
    centroid: [Number(c.lat), Number(c.lon)],
    geofencing: { bbox_radius_km: Number(c.radius_km) },
    demographics: { population: numOrNull(c.population) },
    logistics: {
      trucks_active: numOrNull(c.trucks),
      fuel_price_fcfa_l: numOrNull(c.fuel_price_fcfa),
      depot: c.depot,
      terminal_treatment: c.landfill,
    },
    osm_layers: ['amenity=waste_disposal', 'amenity=recycling', 'landuse=landfill'],
  };
}

function fromConfig(j) {
  if (!j || !j.municipality || !Array.isArray(j.centroid)) throw new Error('Fichier config.json invalide : municipality et centroid sont requis.');
  return {
    slug: slugify(j.municipality),
    name: j.municipality,
    region: j.region || '',
    lat: Number(j.centroid[0]),
    lon: Number(j.centroid[1]),
    radius_km: Number(j.geofencing?.bbox_radius_km || 15),
    population: j.demographics?.population ?? '',
    trucks: j.logistics?.trucks_active ?? '',
    fuel_price_fcfa: j.logistics?.fuel_price_fcfa_l ?? '',
    depot: j.logistics?.depot || null,
    landfill: j.logistics?.terminal_treatment || null,
  };
}

export default function Communes() {
  const { user } = useAuth();
  const toast = useToast();
  const isAdmin = user.role === 'admin';
  const data = useAsync(() => api.get('/api/admin/communes'));
  const [form, setForm] = useState(blank);
  const [editing, setEditing] = useState(null);
  const [busy, setBusy] = useState(false);
  const file = useRef(null);

  useEffect(() => {
    if (data.data && editing == null) {
      const a = data.data.communes.find((c) => c.slug === data.data.active);
      if (a) setForm({ ...blank, ...a, population: a.population ?? '', trucks: a.trucks ?? '', fuel_price_fcfa: a.fuel_price_fcfa ?? '' });
      setEditing(a ? a.slug : false);
    }
  }, [data.data, editing]);

  if (data.loading && !data.data) return <Loading />;
  if (data.error && !data.data) return <div className="page"><ErrorBox error={data.error} retry={data.reload} /></div>;

  const { communes, active } = data.data;
  const set = (k, v) => setForm((f) => ({ ...f, [k]: v }));
  const setPoint = (k, field, v) => setForm((f) => ({ ...f, [k]: { ...(f[k] || { lat: f.lat, lon: f.lon }), [field]: v } }));
  const clean = (c) => ({
    slug: c.slug || slugify(c.name),
    name: c.name.trim(),
    region: c.region || '',
    lat: Number(c.lat),
    lon: Number(c.lon),
    radius_km: Number(c.radius_km),
    population: numOrNull(c.population),
    trucks: numOrNull(c.trucks),
    fuel_price_fcfa: numOrNull(c.fuel_price_fcfa),
    depot: c.depot ? { lat: Number(c.depot.lat), lon: Number(c.depot.lon) } : null,
    landfill: c.landfill ? { name: c.landfill.name || undefined, lat: Number(c.landfill.lat), lon: Number(c.landfill.lon) } : null,
  });

  async function save() {
    if (form.name.trim().length < 2) return toast('Indiquez le nom de la commune.', 'error');
    const next = clean(form);
    const list = communes.some((c) => c.slug === next.slug) ? communes.map((c) => (c.slug === next.slug ? next : c)) : [...communes, next];
    setBusy(true);
    try {
      await api.put('/api/admin/communes', { communes: list });
      toast('Commune enregistrée', 'ok');
      setEditing(next.slug);
      data.reload();
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      setBusy(false);
    }
  }

  async function remove(slug) {
    if (slug === active) return toast('Activez une autre commune avant de supprimer celle-ci.', 'error');
    try {
      await api.put('/api/admin/communes', { communes: communes.filter((c) => c.slug !== slug) });
      toast('Commune supprimée', 'ok');
      setEditing(null);
      data.reload();
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  async function activate(slug) {
    try {
      await api.post(`/api/admin/communes/${slug}/activate`);
      toast('Commune activée : dépôt et décharge mis à jour pour le moteur', 'ok');
      data.reload();
    } catch (e) {
      toast(e.message, 'error');
    }
  }

  async function onFile(e) {
    const f = e.target.files?.[0];
    e.target.value = '';
    if (!f) return;
    try {
      const j = JSON.parse(await f.text());
      setForm({ ...blank, ...fromConfig(j) });
      setEditing('import');
      toast('Configuration chargée. Vérifiez puis enregistrez.', 'ok');
    } catch (err) {
      toast(err.message || 'Fichier illisible', 'error');
    }
  }

  const config = (() => {
    try {
      return toConfig(form);
    } catch {
      return {};
    }
  })();

  return (
    <div className="page">
      <div className="page-head">
        <div>
          <h2>Configuration des communes</h2>
          <p>Chaque commune est décrite par un fichier config.json ouvert. L’activation met à jour le dépôt et la décharge utilisés par le moteur de calcul.</p>
        </div>
        <div className="row">
          <button className="btn" onClick={() => file.current?.click()} disabled={!isAdmin}>
            Importer un config.json
          </button>
          <input ref={file} type="file" accept="application/json,.json" hidden onChange={onFile} />
          <button className="btn primary" disabled={!isAdmin} onClick={() => { setForm(blank); setEditing('new'); }}>
            Nouvelle commune
          </button>
        </div>
      </div>

      <div className="grid g3">
        {communes.map((c) => (
          <Card key={c.slug} style={c.slug === active ? { borderColor: '#47a037', boxShadow: '0 0 0 2px #e4f2e1' } : undefined}>
            <div className="row">
              <h3 style={{ fontSize: 17 }}>{c.name}</h3>
              <span className="sp" />
              {c.slug === active ? <Pill tone="green">Active</Pill> : null}
            </div>
            <div className="muted" style={{ margin: '6px 0 12px' }}>{c.region || '—'} · rayon {c.radius_km} km</div>
            <div className="small muted">
              {c.lat.toFixed(4)}, {c.lon.toFixed(4)}
              <br />
              {c.population != null ? `${nf(c.population)} hab.` : 'Population non renseignée'} · {c.trucks != null ? `${c.trucks} camions` : 'flotte non renseignée'}
            </div>
            <div className="row" style={{ marginTop: 14 }}>
              <button className="btn sm" onClick={() => { setForm({ ...blank, ...c, population: c.population ?? '', trucks: c.trucks ?? '', fuel_price_fcfa: c.fuel_price_fcfa ?? '' }); setEditing(c.slug); }}>
                Modifier
              </button>
              {isAdmin && c.slug !== active ? (
                <button className="btn sm primary" onClick={() => activate(c.slug)}>
                  Activer
                </button>
              ) : null}
              {isAdmin && c.slug !== active ? (
                <button className="btn sm danger" onClick={() => remove(c.slug)}>
                  Supprimer
                </button>
              ) : null}
            </div>
          </Card>
        ))}
      </div>

      <div className="grid g2" style={{ marginTop: 18 }}>
        <Card>
          <CardHead title={editing === 'new' || editing === 'import' ? 'Nouvelle commune' : `Modifier : ${form.name || '—'}`} sub="Spécifications géographiques et logistiques" />
          <div className="stack">
            <div className="field">
              <label>Nom officiel de la collectivité</label>
              <input value={form.name} disabled={!isAdmin} onChange={(e) => { set('name', e.target.value); if (editing === 'new' || editing === 'import') set('slug', slugify(e.target.value)); }} placeholder="Commune de Bobo-Dioulasso" />
            </div>
            <div className="grid g2">
              <div className="field">
                <label>Région</label>
                <input value={form.region} disabled={!isAdmin} onChange={(e) => set('region', e.target.value)} />
              </div>
              <div className="field">
                <label>Identifiant</label>
                <input value={form.slug} disabled={!isAdmin || editing !== 'new'} onChange={(e) => set('slug', slugify(e.target.value))} />
              </div>
              <div className="field">
                <label>Latitude du centre</label>
                <input type="number" step="0.0001" value={form.lat} disabled={!isAdmin} onChange={(e) => set('lat', e.target.value)} />
              </div>
              <div className="field">
                <label>Longitude du centre</label>
                <input type="number" step="0.0001" value={form.lon} disabled={!isAdmin} onChange={(e) => set('lon', e.target.value)} />
              </div>
              <div className="field">
                <label>Rayon du géofencing (km)</label>
                <input type="number" min="1" max="100" value={form.radius_km} disabled={!isAdmin} onChange={(e) => set('radius_km', e.target.value)} />
              </div>
              <div className="field">
                <label>Population</label>
                <input type="number" min="0" value={form.population} disabled={!isAdmin} onChange={(e) => set('population', e.target.value)} />
              </div>
              <div className="field">
                <label>Camions opérationnels</label>
                <input type="number" min="0" value={form.trucks} disabled={!isAdmin} onChange={(e) => set('trucks', e.target.value)} />
              </div>
              <div className="field">
                <label>Carburant (FCFA / L)</label>
                <input type="number" min="0" value={form.fuel_price_fcfa} disabled={!isAdmin} onChange={(e) => set('fuel_price_fcfa', e.target.value)} />
              </div>
            </div>
            <div className="field">
              <label>Dépôt des camions (laisser vide : le centre)</label>
              <div className="grid g2">
                <input type="number" step="0.0001" placeholder="Latitude" value={form.depot?.lat ?? ''} disabled={!isAdmin} onChange={(e) => (e.target.value === '' ? set('depot', null) : setPoint('depot', 'lat', e.target.value))} />
                <input type="number" step="0.0001" placeholder="Longitude" value={form.depot?.lon ?? ''} disabled={!isAdmin} onChange={(e) => setPoint('depot', 'lon', e.target.value)} />
              </div>
            </div>
            <div className="field">
              <label>Décharge ou centre de traitement</label>
              <input placeholder="Nom (facultatif)" value={form.landfill?.name ?? ''} disabled={!isAdmin} onChange={(e) => setPoint('landfill', 'name', e.target.value)} />
              <div className="grid g2">
                <input type="number" step="0.0001" placeholder="Latitude" value={form.landfill?.lat ?? ''} disabled={!isAdmin} onChange={(e) => (e.target.value === '' ? set('landfill', null) : setPoint('landfill', 'lat', e.target.value))} />
                <input type="number" step="0.0001" placeholder="Longitude" value={form.landfill?.lon ?? ''} disabled={!isAdmin} onChange={(e) => setPoint('landfill', 'lon', e.target.value)} />
              </div>
            </div>
            {isAdmin ? (
              <button className="btn primary" onClick={save} disabled={busy}>
                {busy ? 'Enregistrement…' : 'Enregistrer la commune'}
              </button>
            ) : (
              <div className="note">Seul un administrateur peut modifier les communes.</div>
            )}
          </div>
        </Card>
        <Card>
          <CardHead title="Fichier config.json" sub="Standard d’échange ouvert, réutilisable par une autre commune" />
          <div className="code">{JSON.stringify(config, null, 2)}</div>
          <button className="btn dark block" style={{ marginTop: 12 }} onClick={() => saveBlob(new Blob([JSON.stringify(config, null, 2)], { type: 'application/json' }), `config-${form.slug || 'commune'}.json`)}>
            <Icon name="download" size={18} /> Télécharger config.json
          </button>
          <div className="note" style={{ marginTop: 14 }}>
            Les bâtiments et les dépotoirs ne sont pas séparés par commune dans la base. Pour une nouvelle commune, importez ses bâtiments avec <b>kit_commune.py</b> avant d’activer.
          </div>
        </Card>
      </div>
    </div>
  );
}
