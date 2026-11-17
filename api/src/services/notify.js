export async function notifyAuthors(client, dumpId, kind, title, body) {
  await client.query(
    `INSERT INTO notifications (user_id, kind, dump_id, title, body)
     SELECT DISTINCT user_id, $2::text, $1::uuid, $3::text, $4::text FROM reports WHERE dump_id = $1::uuid AND status <> 'rejected'
     ON CONFLICT DO NOTHING`,
    [dumpId, kind, title, body],
  );
}
