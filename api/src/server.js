import { config } from './config.js';
import { createApp } from './app.js';
import { migrate } from './migrate.js';
import { pool } from './db.js';

await migrate();
const server = createApp().listen(config.port, () => console.log(`API sur le port ${config.port}`));

for (const sig of ['SIGINT', 'SIGTERM']) {
  process.on(sig, () => server.close(() => pool.end().then(() => process.exit(0))));
}
