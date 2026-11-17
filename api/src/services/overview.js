import { query } from '../db.js';

export async function getOverview() {
  const [counts, delay, month, rec] = await Promise.all([
    query("SELECT status, count(*)::int AS n, coalesce(sum(est_kg), 0)::float AS kg FROM dumps GROUP BY status"),
    query("SELECT avg(EXTRACT(EPOCH FROM (cleaned_at - first_reported_at)) / 3600.0)::float AS hours FROM dumps WHERE status = 'cleaned'"),
    query("SELECT count(*)::int AS n FROM dumps WHERE status = 'cleaned' AND cleaned_at > now() - interval '30 days'"),
    query("SELECT count(*) FILTER (WHERE recurrence_of IS NOT NULL)::int AS recurrent, count(*)::int AS total FROM dumps WHERE status <> 'rejected'"),
  ]);
  return {
    by_status: Object.fromEntries(counts.rows.map((c) => [c.status, { count: c.n, est_kg: c.kg }])),
    cleaned_last_30_days: month.rows[0].n,
    avg_hours_to_clean: delay.rows[0].hours,
    recurrence_rate: rec.rows[0].total ? rec.rows[0].recurrent / rec.rows[0].total : 0,
  };
}
