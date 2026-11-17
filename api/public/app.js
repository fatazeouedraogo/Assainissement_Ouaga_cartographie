const $ = (id) => document.getElementById(id);
const fmtH = (h) => (h == null ? '—' : h < 48 ? `${Math.round(h)} h` : `${Math.round(h / 24)} j`);

async function json(url) {
  const r = await fetch(url);
  if (!r.ok) throw new Error(url);
  return r.json();
}

function kpi(value, label) {
  const d = document.createElement('div');
  d.className = 'kpi';
  d.innerHTML = '<b></b><span></span>';
  d.firstChild.textContent = value;
  d.lastChild.textContent = label;
  return d;
}

function rows(el, items) {
  el.replaceChildren(...items.map(([a, b]) => {
    const li = document.createElement('li');
    const l = document.createElement('span');
    const r = document.createElement('b');
    l.textContent = a;
    r.textContent = b;
    li.append(l, r);
    return li;
  }));
  if (!items.length) el.innerHTML = '<li><span>Pas encore de données</span></li>';
}

async function main() {
  const map = L.map('map', { zoomControl: true }).setView([12.3714, -1.5197], 12);
  L.tileLayer('https://tile.openstreetmap.org/{z}/{x}/{y}.png', { maxZoom: 19, attribution: '© contributeurs OpenStreetMap' }).addTo(map);
  const [ov, geo, hot, lead] = await Promise.all([
    json('/api/public/overview'),
    json('/api/public/dumps.geojson'),
    json('/api/public/hotspots'),
    json('/api/public/leaderboard'),
  ]);
  const by = ov.by_status || {};
  $('kpis').append(
    kpi((by.verified?.count || 0) + (by.scheduled?.count || 0), 'dépotoirs à traiter'),
    kpi(ov.cleaned_last_30_days, 'nettoyés en 30 jours'),
    kpi(fmtH(ov.avg_hours_to_clean), 'délai moyen de traitement'),
    kpi(`${Math.round((ov.recurrence_rate || 0) * 100)} %`, 'de récidive'),
  );
  const color = { verified: '#c8372d', scheduled: '#2f6db5', cleaned: '#2e7d5b' };
  for (const f of geo.features) {
    const [lon, lat] = f.geometry.coordinates;
    L.circleMarker([lat, lon], { radius: 6 + (f.properties.size === 'large' ? 5 : f.properties.size === 'medium' ? 2 : 0), color: '#17262b', weight: 1.5, fillColor: color[f.properties.status], fillOpacity: 0.9 })
      .bindPopup(`${f.properties.status} · ~${Math.round(f.properties.est_kg)} kg`)
      .addTo(map);
  }
  rows($('hot'), hot.hotspots.slice(0, 6).map((h) => [`${h.lat.toFixed(3)}, ${h.lon.toFixed(3)}`, `${h.recurrences} récidive(s)`]));
  rows($('lead'), lead.leaders.slice(0, 8).map((l) => [`${l.rank}. ${l.name}`, `${l.points} pts`]));
}

main().catch(() => {
  $('kpis').append(kpi('—', 'données momentanément indisponibles'));
});
