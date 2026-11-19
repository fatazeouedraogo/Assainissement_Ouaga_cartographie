import { useState } from 'react';
import { api, session } from '../api.js';
import { useAuth } from '../App.jsx';

export default function Login() {
  const { setUser } = useAuth();
  const [phone, setPhone] = useState('');
  const [password, setPassword] = useState('');
  const [server, setServer] = useState(session.base());
  const [more, setMore] = useState(false);
  const [error, setError] = useState('');
  const [busy, setBusy] = useState(false);

  async function submit(e) {
    e.preventDefault();
    setBusy(true);
    setError('');
    try {
      session.setBase(server.trim());
      const j = await api.post('/api/auth/login', { phone: phone.replace(/\s+/g, ''), password });
      if (!['admin', 'verifier'].includes(j.user.role)) {
        session.clear();
        throw new Error('Ce compte n’a pas accès à l’administration.');
      }
      session.setToken(j.token);
      setUser(j.user);
    } catch (err) {
      setError(err.message);
    } finally {
      setBusy(false);
    }
  }

  return (
    <div className="login">
      <form className="box stack" onSubmit={submit}>
        <img src="/admin/logo.png" alt="OuagaClean" />
        <div style={{ textAlign: 'center' }}>
          <h2 style={{ fontSize: 22 }}>Espace d’administration</h2>
          <div className="muted" style={{ marginTop: 4 }}>
            Réservé aux vérificateurs et administrateurs
          </div>
        </div>
        <div className="field">
          <label>Téléphone</label>
          <input value={phone} onChange={(e) => setPhone(e.target.value)} placeholder="+226 70 00 00 01" autoComplete="username" required />
        </div>
        <div className="field">
          <label>Mot de passe</label>
          <input type="password" value={password} onChange={(e) => setPassword(e.target.value)} autoComplete="current-password" required />
        </div>
        {error ? <div className="err">{error}</div> : null}
        <button className="btn primary block" disabled={busy}>
          {busy ? 'Connexion…' : 'Se connecter'}
        </button>
        <button type="button" className="btn sm" onClick={() => setMore(!more)}>
          Adresse du serveur
        </button>
        {more ? (
          <div className="field">
            <label>API (vide = ce serveur)</label>
            <input value={server} onChange={(e) => setServer(e.target.value)} placeholder="http://192.168.1.10:3000" />
          </div>
        ) : null}
      </form>
    </div>
  );
}
