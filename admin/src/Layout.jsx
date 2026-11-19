import { useEffect } from 'react';
import { NavLink, Outlet, useLocation } from 'react-router-dom';
import { api, download } from './api.js';
import { useAuth } from './App.jsx';
import { Icon } from './icons.jsx';
import { useAsync } from './lib.js';
import { useToast } from './ui.jsx';

const TITLES = {
  '/': ['Tableau de bord', 'Pilotage de la collecte et état des dépotoirs'],
  '/carte': ['Carte & tournées', 'Dépotoirs, priorités et tournées du dernier plan'],
  '/verification': ['Vérification & anti-pièges', 'Modération des signalements et journal de défense'],
  '/parametres': ['Paramètres & aléas', 'Réglages du moteur, imprévus et comparaison de scénarios'],
  '/simulation': ['Scénarios 30 jours', 'Simulation multi-agents du dernier plan'],
  '/communes': ['Communes', 'Configuration territoriale et export config.json'],
};

export default function Layout() {
  const { user, logout } = useAuth();
  const toast = useToast();
  const { pathname } = useLocation();
  const pending = useAsync(() => api.get('/api/dumps?status=pending&limit=300'), []);
  const communes = useAsync(() => api.get('/api/admin/communes'), []);
  const notifs = useAsync(() => api.get('/api/notifications').catch(() => null), []);

  useEffect(() => {
    const t = setInterval(pending.reload, 60000);
    return () => clearInterval(t);
  }, [pending.reload]);

  const count = pending.data?.features?.length || 0;
  const active = communes.data?.communes?.find((c) => c.slug === communes.data.active);
  const [title, sub] = TITLES[pathname] || TITLES['/'];
  const unread = notifs.data?.unread || 0;

  const item = (to, icon, label, badge) => (
    <NavLink to={to} end={to === '/'}>
      <Icon name={icon} />
      <span>{label}</span>
      {badge ? <span className="badge">{badge}</span> : null}
    </NavLink>
  );

  return (
    <div className="shell">
      <aside className="side">
        <div className="brand">
          <img src="/admin/logo.png" alt="OuagaClean" />
        </div>
        <nav className="nav">
          <div className="nav-title">PILOTAGE</div>
          {item('/', 'grid', 'Tableau de bord')}
          {item('/carte', 'map', 'Carte & tournées')}
          {item('/verification', 'shield', 'Vérification', count || null)}
          <div className="nav-title">SIMULATION</div>
          {item('/parametres', 'sliders', 'Paramètres & aléas')}
          {item('/simulation', 'pulse', 'Scénarios 30 jours')}
          <div className="nav-title">BIEN COMMUN</div>
          {item('/communes', 'building', 'Communes')}
        </nav>
        <div className="grow" />
        <div className="open-card">
          <h4>Bien commun open source</h4>
          <p>Versez les dépotoirs vérifiés vers OpenStreetMap, sous licence ODbL.</p>
          <button
            className="btn primary block"
            onClick={() => download('/api/public/dumps.geojson', 'dechets-ouagadougou.geojson').catch((e) => toast(e.message, 'error'))}
          >
            <Icon name="download" size={18} /> Exporter GeoJSON
          </button>
        </div>
      </aside>
      <div className="main">
        <header className="top">
          <div>
            <h1>{title}</h1>
            <div className="sub">{sub}</div>
          </div>
          <div className="sp" />
          <span className="chip">
            <Icon name="building" size={18} /> {active ? active.name.replace(/^Commune (de |d’)?/i, '') : '—'}
          </span>
          <span className="chip" title="Notifications non lues">
            <Icon name="bell" size={18} /> {unread}
          </span>
          <div className="user">
            <div>
              <div style={{ fontWeight: 700 }}>{user.name}</div>
              <div className="muted small">{user.role === 'admin' ? 'Administrateur' : 'Vérificateur'}</div>
            </div>
            <div className="avatar">{user.name?.[0]?.toUpperCase()}</div>
            <button className="btn sm" onClick={logout} title="Se déconnecter">
              <Icon name="logout" size={16} />
            </button>
          </div>
        </header>
        <Outlet context={{ refreshPending: pending.reload }} />
      </div>
    </div>
  );
}
