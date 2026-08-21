import { Router } from 'express';

export const healthRouter = Router();

// GET /api/v1/health -> { status: 'ok' }
healthRouter.get('/health', (_req, res) => {
  res.status(200).json({ status: 'ok' });
});
