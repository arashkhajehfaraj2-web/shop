import 'reflect-metadata';
import { Logger } from '@nestjs/common';
import { NestFactory } from '@nestjs/core';
import { AppModule } from './app.module';
import { GlobalExceptionFilter } from './common/filters/global-exception.filter';

async function bootstrap(): Promise<void> {
  const app = await NestFactory.create(AppModule);

  app.setGlobalPrefix('api/v1');
  app.useGlobalFilters(new GlobalExceptionFilter());

  const nodeEnv = process.env.NODE_ENV ?? 'development';
  const corsOrigin = process.env.CORS_ORIGIN?.trim();

  if (nodeEnv === 'production' && !corsOrigin) {
    throw new Error('CORS_ORIGIN must be configured in production.');
  }

  app.enableCors({
    origin: corsOrigin
      ? corsOrigin.split(',').map((origin) => origin.trim()).filter(Boolean)
      : nodeEnv !== 'production',
  });

  app.enableShutdownHooks();

  const port = Number(process.env.PORT ?? 3000);

  await app.listen(port);

  new Logger('Bootstrap').log(
    `API listening on http://localhost:${port}/api/v1`,
  );
}

void bootstrap().catch((error: unknown) => {
  const logger = new Logger('Bootstrap');

  logger.error(
    'Application failed to start',
    error instanceof Error ? error.stack : undefined,
  );

  process.exitCode = 1;
});
