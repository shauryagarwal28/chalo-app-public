import http from 'node:http';
import { createApp } from './app';
import { env } from './config/env';
import { connectRedis } from './lib/redis';
import { createWebSocketServer } from './websocket/server';
import { startCleanupSweep } from './websocket/cleanupSweep';

async function main(): Promise<void> {
  // Connect before building/serving the app — Task 2's routes (otp/user/
  // token services) assume a live Redis connection, don't lazily connect
  // per-request.
  await connectRedis();

  // Task 9 (reconnect/cleanup hardening pass): starts the periodic party:*
  // Redis key-set sanity sweep (websocket/cleanupSweep.ts) — observability
  // only, logs a warning, never mutates anything. Started once here,
  // alongside the Redis connection it depends on.
  startCleanupSweep();

  const app = createApp();

  // The WS server (Task 3) is mounted on the same http.Server instance as
  // the Express app, in the same Node process — not a separate listener/
  // process, per backend-mvp-plan.md Task 3's explicit "unnecessary
  // complexity at this scale" call. `http.createServer(app)` is needed
  // (rather than `app.listen(...)` directly) because `ws`'s WebSocketServer
  // needs a reference to the underlying http.Server to hook its 'upgrade'
  // handling into.
  const server = http.createServer(app);
  createWebSocketServer(server);

  server.listen(env.PORT, () => {
    // eslint-disable-next-line no-console
    console.log(`Chalo backend listening on port ${env.PORT} (${env.NODE_ENV})`);
  });
}

main().catch((err) => {
  // eslint-disable-next-line no-console
  console.error('[startup] failed to start server', err);
  process.exit(1);
});
