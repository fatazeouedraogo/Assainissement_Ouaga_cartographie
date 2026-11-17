import PDFDocument from 'pdfkit';

const clean = (s) => String(s ?? '').replace(/[’‘]/g, "'").replace(/[–—−]/g, '-').replace(/≤/g, '<=').replace(/₂/g, '2').replace(/[^\x20-\xFF\n]/g, '');
const pct = (v) => `${(v * 100).toFixed(1)} %`;
const money = (v) => `${Math.round(v).toString().replace(/\B(?=(\d{3})+(?!\d))/g, ' ')} FCFA`;

export function buildReport({ plan, simulation, warnings = [], overview, generatedAt = new Date() }) {
  const doc = new PDFDocument({ size: 'A4', margin: 48, info: { Title: 'Note de décision - assainissement de Ouagadougou' } });
  const m = plan.metrics;
  const s = simulation?.summary;
  const ink = '#17262B';

  doc.rect(0, 0, 595, 14).fill(ink);
  doc.fillColor(ink).font('Helvetica-Bold').fontSize(20).text(clean('Note de décision'), 48, 40);
  doc.font('Helvetica').fontSize(11).fillColor('#51636A').text(clean(`Assainissement de Ouagadougou - ${generatedAt.toLocaleDateString('fr-FR')}`));
  doc.moveDown(1.2);

  const line = (label, value, bad = false) => {
    const y = doc.y;
    doc.font('Helvetica').fontSize(11).fillColor(ink).text(clean(label), 48, y, { width: 300 });
    doc.font('Helvetica-Bold').fillColor(bad ? '#C8372D' : ink).text(clean(value), 350, y, { width: 200, align: 'right' });
    doc.moveDown(0.45);
  };
  const h = (t) => {
    doc.moveDown(0.8).font('Helvetica-Bold').fontSize(13).fillColor(ink).text(clean(t), 48);
    doc.moveTo(48, doc.y + 2).lineTo(547, doc.y + 2).strokeColor('#CBD1C6').stroke();
    doc.moveDown(0.6);
  };

  if (plan.applied_events?.length) {
    h('Hypothèses de ce scénario');
    doc.font('Helvetica').fontSize(11).fillColor(ink).text(clean(plan.applied_events.join(', ')));
  }
  if (warnings.length) {
    doc.moveDown(0.4).font('Helvetica-Bold').fontSize(10).fillColor('#C8372D').text(clean('Données provisoires : ' + warnings.join(', ')));
  }

  h('Situation en un coup d\'oeil');
  if (overview) {
    const by = overview.by_status || {};
    line('Dépotoirs à traiter (vérifiés ou programmés)', String((by.verified?.count || 0) + (by.scheduled?.count || 0)));
    line('Nettoyés sur les 30 derniers jours', String(overview.cleaned_last_30_days ?? 0));
    line('Taux de récidive', pct(overview.recurrence_rate || 0));
  }

  h('Plan de collecte');
  line('Points de regroupement', String(m.points));
  line('Couverture à pied (marche maximale)', pct(m.coverage));
  line('Équité périphérie / centre', pct(m.equity_index), m.equity_index < 0.8);
  line('Coût mensuel', money(m.cost_per_month), !m.within_budget);
  line('Budget mensuel', money(m.budget_month));
  line('Distance parcourue par jour', `${Math.round(m.km_per_day)} km`);
  line('Émissions de CO2 par jour', `${Math.round(m.co2_kg_per_day)} kg`);
  if (m.unserved_points > 0) line('Points non desservis avec cette flotte', String(m.unserved_points), true);
  line('Prix d\'équilibre de l\'abonnement', `${money(m.subscription_break_even_month)} / mois`);

  if (s) {
    h(`Simulation (${simulation.replications} répétitions, ${simulation.horizon_days} jours)`);
    const band = (k) => `${pct(s[k].mean)} (${pct(s[k].p05)} à ${pct(s[k].p95)})`;
    line('Déchets collectés', band('collection_rate'));
    line('Déchets partis en dépotoirs', band('leakage_rate'), s.leakage_rate.mean > 0.1);
    line('Personnes vivant à proximité d\'un dépotoir actif', String(Math.round(s.exposed_people.mean)), s.exposed_people.mean > 0);
    if (s.revenue_month.mean > 0) line('Revenu mensuel de la valorisation', money(s.revenue_month.mean));
  }

  h('Lecture');
  const lines = [];
  if (!m.within_budget) lines.push(`Le coût dépasse le budget de ${money(m.cost_per_month - m.budget_month)} par mois : réduire la fréquence ou la flotte, ou relever le budget.`);
  if (m.equity_index < 0.8) lines.push('Les quartiers périphériques sont moins bien couverts que le centre : augmenter la priorité aux périphéries.');
  if (m.unserved_points > 0) lines.push('Certains points ne sont pas desservis : ajouter des camions ou des tricycles.');
  if (s && s.leakage_rate.mean > 0.1) lines.push('Plus de 10 % des déchets finissent en dépotoirs : renforcer la collecte ou les abonnements.');
  if (!lines.length) lines.push('Aucune alerte majeure avec ces hypothèses.');
  doc.font('Helvetica').fontSize(11).fillColor(ink);
  for (const l of lines) doc.text(clean('- ' + l), { width: 499 }).moveDown(0.3);

  doc.moveDown(1).fontSize(9).fillColor('#51636A').text(clean('Les paramètres par défaut sont des hypothèses à confirmer avec la mairie. Les fourchettes représentent les 5e et 95e percentiles des simulations.'), { width: 499 });
  doc.end();
  return doc;
}
