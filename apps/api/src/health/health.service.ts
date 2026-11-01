import { Injectable, Logger } from '@nestjs/common';
import { PrismaService } from '../prisma/prisma.service';
import { RedisService } from '../redis/redis.service';

export interface DatabaseHealth {
  status: 'up' | 'down';
  latencyMs?: number;
}

export interface RedisHealth {
  status: 'up' | 'down';
  latencyMs?: number;
}

@Injectable()
export class HealthService {
  private readonly logger = new Logger(HealthService.name);

  constructor(
    private readonly prisma: PrismaService,
    private readonly redis: RedisService,
  ) {}

  async checkDatabase(): Promise<DatabaseHealth> {
    const startedAt = Date.now();

    try {
      await this.prisma.$queryRaw`SELECT 1`;

      return {
        status: 'up',
        latencyMs: Date.now() - startedAt,
      };
    } catch (error: unknown) {
      this.logger.error(
        `Database health check failed: ${error instanceof Error ? error.name : 'unknown error'}`,
        error instanceof Error ? error.stack : undefined,
      );

      return { status: 'down' };
    }
  }

  async checkRedis(): Promise<RedisHealth> {
    const startedAt = Date.now();

    try {
      await this.redis.ping();

      return {
        status: 'up',
        latencyMs: Date.now() - startedAt,
      };
    } catch (error: unknown) {
      this.logger.error(
        `Redis health check failed: ${error instanceof Error ? error.name : 'unknown error'}`,
        error instanceof Error ? error.stack : undefined,
      );

      return { status: 'down' };
    }
  }
}