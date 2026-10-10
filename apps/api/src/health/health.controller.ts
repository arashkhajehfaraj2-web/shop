import {
  Controller,
  Get,
  HttpStatus,
  Res,
} from '@nestjs/common';
import type { Response } from 'express';
import { HealthService } from './health.service';

@Controller('health')
export class HealthController {
  constructor(private readonly health: HealthService) {}

  /** GET /api/v1/health — 200 if DB is up, 503 otherwise. */
  @Get()
  async check(@Res({ passthrough: true }) response: Response) {
    const database = await this.health.checkDatabase();

    const body = {
      status: database.status === 'up' ? 'ok' : 'error',
      timestamp: new Date().toISOString(),
      uptimeSeconds: Math.round(process.uptime() * 100) / 100,
      checks: { database },
    };

    if (database.status !== 'up') {
      response.status(HttpStatus.SERVICE_UNAVAILABLE);
    }

    return body;
  }
}
