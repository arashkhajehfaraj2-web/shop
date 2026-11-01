import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { ConfigModule, ConfigService } from '@nestjs/config';
import { validate } from './config/env.validation';
import { HealthModule } from './health/health.module';
import { PrismaModule } from './prisma/prisma.module';
import { RedisModule } from './redis/redis.module';
import { QueuesModule } from './queues/queues.module';

@Module({
  imports: [
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      envFilePath: ['.env', '../../.env'],
      validate,
    }),

    BullModule.forRootAsync({
      imports: [ConfigModule],
      inject: [ConfigService],
      useFactory: (configService: ConfigService) => {
        const redisUrl = new URL(
          configService.getOrThrow<string>('REDIS_URL'),
        );

        const databasePath = redisUrl.pathname.replace(/^\/+/, '');
        const db =
          databasePath === '' ? undefined : Number(databasePath);

        if (
          db !== undefined &&
          (!Number.isInteger(db) || db < 0)
        ) {
          throw new Error(
            'REDIS_URL must contain a valid Redis database number',
          );
        }

        return {
          connection: {
            host: redisUrl.hostname,
            port: Number(redisUrl.port || 6379),

            ...(redisUrl.username
              ? { username: decodeURIComponent(redisUrl.username) }
              : {}),

            ...(redisUrl.password
              ? { password: decodeURIComponent(redisUrl.password) }
              : {}),

            ...(db !== undefined ? { db } : {}),

            ...(redisUrl.protocol === 'rediss:'
              ? { tls: {} }
              : {}),
          },
        };
      },
    }),

    PrismaModule,
    RedisModule,
    QueuesModule,
    HealthModule,
  ],
})
export class AppModule {}