import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { Redis } from 'ioredis';

@Injectable()
export class RedisService implements OnModuleInit, OnModuleDestroy {
  private readonly logger = new Logger(RedisService.name);
  private readonly client: Redis;

  constructor(configService: ConfigService) {
    const redisUrl = configService.getOrThrow<string>('REDIS_URL');

    this.client = new Redis(redisUrl, {
      lazyConnect: true,
      enableReadyCheck: true,
      maxRetriesPerRequest: 3,
    });

    this.client.on('error', (error: Error) => {
      this.logger.error(`Redis client error: ${error.name}`);
    });

    this.client.on('reconnecting', (delay: number) => {
      this.logger.warn(`Redis reconnecting in ${delay}ms`);
    });
  }

  async onModuleInit(): Promise<void> {
    await this.client.connect();
    this.logger.log('Redis connection established');
  }

  async onModuleDestroy(): Promise<void> {
    if (this.client.status === 'ready') {
      await this.client.quit();
    } else {
      this.client.disconnect();
    }
  }

  async ping(): Promise<string> {
    return this.client.ping();
  }

  getClient(): Redis {
    return this.client;
  }
}