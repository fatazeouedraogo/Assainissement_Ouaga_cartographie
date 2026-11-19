import { createContext, useCallback, useContext, useEffect, useState } from 'react';
import { BrowserRouter, Navigate, Route, Routes } from 'react-router-dom';
import { api, session } from './api.js';
import { Loading, ToastProvider } from './ui.jsx';
import Layout from './Layout.jsx';
import Login from './pages/Login.jsx';
import Dashboard from './pages/Dashboard.jsx';
import MapPage from './pages/MapPage.jsx';
import Verification from './pages/Verification.jsx';
import Params from './pages/Params.jsx';
import Simulation from './pages/Simulation.jsx';
import Communes from './pages/Communes.jsx';

const AuthCtx = createContext(null);
export const useAuth = () => useContext(AuthCtx);

export default function App() {
  const [user, setUser] = useState(null);
  const [ready, setReady] = useState(false);

  const logout = useCallback(() => {
    session.clear();
    setUser(null);
  }, []);

  useEffect(() => {
    const onAuth = () => setUser(null);
    window.addEventListener('oc-auth', onAuth);
    return () => window.removeEventListener('oc-auth', onAuth);
  }, []);

  useEffect(() => {
    if (!session.token()) return setReady(true);
    api
      .get('/api/auth/me')
      .then((j) => {
        const u = j && j.user ? j.user : j;
        setUser(['admin', 'verifier'].includes(u?.role) ? u : null);
      })
      .catch(() => setUser(null))
      .finally(() => setReady(true));
  }, []);

  if (!ready) return <Loading />;

  return (
    <ToastProvider>
      <AuthCtx.Provider value={{ user, setUser, logout }}>
        <BrowserRouter basename="/admin">
          {!user ? (
            <Login />
          ) : (
            <Routes>
              <Route element={<Layout />}>
                <Route index element={<Dashboard />} />
                <Route path="carte" element={<MapPage />} />
                <Route path="verification" element={<Verification />} />
                <Route path="parametres" element={<Params />} />
                <Route path="simulation" element={<Simulation />} />
                <Route path="communes" element={<Communes />} />
                <Route path="*" element={<Navigate to="/" replace />} />
              </Route>
            </Routes>
          )}
        </BrowserRouter>
      </AuthCtx.Provider>
    </ToastProvider>
  );
}
