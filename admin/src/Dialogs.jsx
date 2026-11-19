import { useState } from 'react';
import { api } from './api.js';
import { REJECT_CHOICES, REJECT_LABELS, SIZE, WASTE, kg } from './lib.js';
import { Modal, useToast } from './ui.jsx';

export function ScheduleDialog({ dump, onClose, onDone }) {
  const toast = useToast();
  const tomorrow = new Date(Date.now() + 86400000).toISOString().slice(0, 10);
  const [date, setDate] = useState(tomorrow);
  const [busy, setBusy] = useState(false);

  async function save() {
    setBusy(true);
    try {
      await api.post(`/api/dumps/${dump.id}/schedule`, { date });
      toast('Passage programmé', 'ok');
      onDone();
    } catch (e) {
      toast(e.message, 'error');
    } finally {
      setBusy(false);
    }
  }

  return (
    <Modal title="Programmer un passage" onClose={onClose}>
      <div className="stack">
        <div className="muted">
          {SIZE[dump.size] || dump.size} · {WASTE[dump.waste_type] || dump.waste_type} · {kg(dump.est_kg)}
        </div>
        <div className="field">
          <label>Date du passage</label>
          <input type="date" min={tomorrow} value={date} onChange={(e) => setDate(e.target.value)} />
        </div>
        <div className="row">
          <button className="btn" onClick={onClose}>
            Annuler
          </button>
          <div className="sp" />
          <button className="btn primary" disabled={busy || !date} onClick={save}>
            Programmer
          </button>
        </div>
      </div>
    </Modal>
  );
}

export function RejectDialog({ title = 'Motif du rejet', onClose, onConfirm }) {
  const [choice, setChoice] = useState('rien_vu');
  const [text, setText] = useState('');
  return (
    <Modal title={title} onClose={onClose}>
      <div className="stack">
        <div className="field">
          <label>Motif</label>
          <select value={choice} onChange={(e) => setChoice(e.target.value)}>
            {REJECT_CHOICES.map((k) => (
              <option key={k} value={k}>
                {REJECT_LABELS[k]}
              </option>
            ))}
          </select>
        </div>
        <div className="field">
          <label>Précision (facultatif)</label>
          <input value={text} onChange={(e) => setText(e.target.value)} maxLength={150} />
        </div>
        <div className="row">
          <button className="btn" onClick={onClose}>
            Annuler
          </button>
          <div className="sp" />
          <button className="btn danger" onClick={() => onConfirm(choice, `${REJECT_LABELS[choice]}${text ? ` — ${text}` : ''}`)}>
            Rejeter
          </button>
        </div>
      </div>
    </Modal>
  );
}
