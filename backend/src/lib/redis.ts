import { createClient, type RedisClientType } from 'redis';
import { env } from '../config/env';

/**
 * Single shared Redis client for the whole process — every service
 * (otp/user/token, and Task 3+'s WS connection/party state) imports this
 * rather than creating its own connection.
 */
export const redisClient: RedisClientType = createClient({ url: env.REDIS_URL });

redisClient.on('error', (err) => {
  // eslint-disable-next-line no-console
  console.error('[redis] client error', err);
});

export async function connectRedis(): Promise<void> {
  if (!redisClient.isOpen) {
    await redisClient.connect();
  }
}

export async function disconnectRedis(): Promise<void> {
  if (redisClient.isOpen) {
    await redisClient.quit();
  }
}
