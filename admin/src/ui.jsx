import { createContext, useCallback, useContext, useState } from 'react';

export function Card({ children, className = '', ...rest }) {
  return (
    <div className={`card ${className}`} {...rest}>
      {children}
    </div>
  );
}

export function CardHead({ title, sub, right }) {
  return (
    <div className="head">
      <div>
        <h3>{title}</h3>
        {sub ? <p>{sub}</p> : null}
      </div>
      {right}
    </div>
  );
}

export function Kpi({ label, value, foot, icon, hero, tone }) {
  return (
    <div className={`card kpi ${hero ? 'hero' : ''}`}>
      <div className="label">
        <span>{label}</span>
        {icon ? <span>{icon}</span> : null}
      </div>
      <div className="value" style={tone ? { color: tone } : undefined}>
        {value}
      </div>
      <div className="foot">{foot}</div>
    </div>
  );
}

export const Pill = ({ tone = '', children }) => <span className={`pill ${tone}`}>{children}</span>;
export const Spinner = () => <span className="spinner" />;
export const Loading = () => (
  <div className="center">
    <Spinner />
  </div>
);

export function Empty({ title, children, action }) {
  return (
    <div className="empty">
      <h4>{title}</h4>
      <div>{children}</div>
      {action ? <div style={{ marginTop: 14 }}>{action}</div> : null}
    </div>
  );
}

export const ErrorBox = ({ error, retry }) => (
  <div className="err">
    {error?.message || 'Une erreur est survenue.'}
    {retry ? (
      <button className="btn sm" style={{ marginLeft: 12 }} onClick={retry}>
        Réessayer
      </button>
    ) : null}
  </div>
);

export function Seg({ value, onChange, options }) {
  return (
    <div className="seg">
      {options.map(([v, label]) => (
        <button key={v} className={value === v ? 'on' : ''} onClick={() => onChange(v)}>
          {label}
        </button>
      ))}
    </div>
  );
}

export function Switch({ checked, onChange }) {
  return (
    <label className="switch">
      <input type="checkbox" checked={checked} onChange={(e) => onChange(e.target.checked)} />
      <span />
    </label>
  );
}

export function Slider({ label, value, min, max, step, unit, onChange, format }) {
  const shown = format ? format(value) : `${Number(value).toLocaleString('fr-FR', { maximumFractionDigits: 2 })}${unit ? ` ${unit}` : ''}`;
  return (
    <div className="slider">
      <div className="top-row">
        <span className="name">{label}</span>
        <span className="val">{shown}</span>
      </div>
      <input type="range" min={min} max={max} step={step} value={value} onChange={(e) => onChange(Number(e.target.value))} />
      <div className="ends">
        <span>{min}</span>
        <span>{max}</span>
      </div>
    </div>
  );
}

export function Modal({ title, onClose, children }) {
  return (
    <div className="modal-back" onMouseDown={(e) => e.target === e.currentTarget && onClose()}>
      <div className="modal">
        <h3>{title}</h3>
        {children}
      </div>
    </div>
  );
}

const ToastCtx = createContext(() => {});
export const useToast = () => useContext(ToastCtx);

export function ToastProvider({ children }) {
  const [items, setItems] = useState([]);
  const push = useCallback((message, kind = '') => {
    const id = Math.random();
    setItems((s) => [...s, { id, message, kind }]);
    setTimeout(() => setItems((s) => s.filter((x) => x.id !== id)), 4200);
  }, []);
  return (
    <ToastCtx.Provider value={push}>
      {children}
      <div className="toasts">
        {items.map((t) => (
          <div key={t.id} className={`toast ${t.kind}`}>
            {t.message}
          </div>
        ))}
      </div>
    </ToastCtx.Provider>
  );
}
