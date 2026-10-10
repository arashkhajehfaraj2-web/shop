import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';

export interface DatabaseHealth {
  status: 'up' | 'down';
  latencyMs?: number;
}

@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);

  constructor(private readonly prisma: PrismaService) {}

  async checkDatabase(): Promise<DatabaseHealth> {
    const startedAt = Date.now();

    try {
      await this.prisma.$queryRaw`SELECT 1`;

      return {
        status: 'up',
        latencyMs: Date.now() - startedAt,
      };
    } catch (error: unknown) {
      // Log details only on the server; never expose DB errors over HTTP.
      this.logger.error(
        `Database health check failed: ${error instanceof Error ? error.name : 'unknown error'}`,
        error instanceof Error ? error.stack : undefined,
      );

      return { status: 'down' };
    }
  }
}
