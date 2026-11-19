import { useCallback, useEffect, useRef, useState } from 'react';

export const nf = (v, d = 0) => (v == null || Number.isNaN(Number(v)) ? '—' : Number(v).toLocaleString('fr-FR', { maximumFractionDigits: d }));
export const pct = (v, d = 0) => (v == null ? '—' : `${(v * 100).toFixed(d).replace('.', ',')} %`);
export const kg = (v) => (v == null ? '—' : v >= 1000 ? `${(v / 1000).toFixed(1).replace('.', ',')} t` : `${Math.round(v)} kg`);
export const fcfa = (v) => (v == null ? '—' : Math.abs(v) >= 1e6 ? `${(v / 1e6).toFixed(1).replace('.', ',')} M FCFA` : `${Math.round(v).toLocaleString('fr-FR')} FCFA`);

export function ago(iso) {
  const t = iso ? new Date(iso).getTime() : NaN;
  if (Number.isNaN(t)) return '';
  const m = Math.round((Date.now() - t) / 60000);
  if (m < 1) return 'à l’instant';
  if (m < 60) return `il y a ${m} min`;
  if (m < 1440) return `il y a ${Math.round(m / 60)} h`;
  return `il y a ${Math.round(m / 1440)} j`;
}

export const dateFr = (iso) => (iso ? new Date(iso).toLocaleDateString('fr-FR') : '—');
export const hm = (iso) => (iso ? new Date(iso).toLocaleTimeString('fr-FR', { hour: '2-digit', minute: '2-digit' }) : '');

export const STATUS = {
  pending: { label: 'En attente', color: '#2fb0e6' },
  verified: { label: 'Confirmé', color: '#d64545' },
  scheduled: { label: 'Programmé', color: '#f2a516' },
  cleaned: { label: 'Nettoyé', color: '#2c7a2f' },
  rejected: { label: 'Rejeté', color: '#8fa0b3' },
};
export const SIZE = { small: 'Petit', medium: 'Moyen', large: 'Gros' };
export const WASTE = { household: 'Ménagers', rubble: 'Gravats', plastic: 'Plastiques', organic: 'Organiques', mixed: 'Mélangés' };

export const REASONS = {
  hors_zone: 'Hors zone (géofencing)',
  photo_absente: 'Photo absente',
  photo_illisible: 'Photo illisible',
  doublon_meme_auteur: 'Doublon du même auteur',
  photo_reutilisee: 'Photo déjà utilisée',
  photo_floue: 'Photo floue',
  photo_sombre: 'Photo trop sombre',
  contenu_douteux: 'Contenu douteux',
  photo_copie_suspecte: 'Copie suspecte d’une photo',
  gps_imprecis: 'GPS imprécis',
  deplacement_impossible: 'Déplacement impossible',
  analyse_indisponible: 'Analyse de photo indisponible',
};
export const reason = (k) => REASONS[k] || k;

export const REJECT_CHOICES = ['batiment', 'route', 'eau', 'vegetation', 'rien_vu', 'deja_signale', 'autre'];
export const REJECT_LABELS = { batiment: 'Bâtiment', route: 'Route', eau: 'Eau', vegetation: 'Végétation', rien_vu: 'Rien d’anormal', deja_signale: 'Déjà signalé', autre: 'Autre' };

export const EVENTS = {
  truck_breakdown: { label: 'Panne de camions', hint: 'Retire des camions de la flotte', unit: 'camion(s)', value: 2, min: 1, max: 20, step: 1 },
  rain_season: { label: 'Saison des pluies', hint: 'Pistes ralenties, priorité aux caniveaux', value: null },
  more_trucks: { label: 'Camions supplémentaires', hint: 'Renforce la flotte', unit: 'camion(s)', value: 2, min: 1, max: 20, step: 1 },
  budget_cut: { label: 'Baisse du budget', hint: 'Réduit le budget mensuel', unit: '%', value: 0.2, min: 0.05, max: 0.8, step: 0.05, percent: true },
  subscription_drop: { label: 'Baisse des abonnements', hint: 'Moins de ménages abonnés', unit: '%', value: 0.2, min: 0.05, max: 0.8, step: 0.05, percent: true },
};

export function bandRows(series, key, scale = 1) {
  const s = series && series[key];
  if (!s) return [];
  return s.mean.map((m, i) => ({
    day: i + 1,
    mean: +(m * scale).toFixed(3),
    lo: +(s.p05[i] * scale).toFixed(3),
    hi: +(s.p95[i] * scale).toFixed(3),
    band: [+(s.p05[i] * scale).toFixed(3), +(s.p95[i] * scale).toFixed(3)],
  }));
}

export function useAsync(fn, deps = []) {
  const [state, setState] = useState({ data: undefined, error: null, loading: true });
  const alive = useRef(true);
  const run = useCallback(() => {
    setState((s) => ({ ...s, loading: true, error: null }));
    fn().then(
      (data) => alive.current && setState({ data, error: null, loading: false }),
      (error) => alive.current && setState((s) => ({ data: s.data, error, loading: false })),
    );
    // eslint-disable-next-line react-hooks/exhaustive-deps
  }, deps);
  useEffect(() => {
    alive.current = true;
    run();
    return () => {
      alive.current = false;
    };
  }, [run]);
  return { ...state, reload: run };
}

export const eventPayload = (key, value) => {
  const def = EVENTS[key];
  const v = value ?? def.value;
  return v == null ? { kind: key } : { kind: key, value: v };
};