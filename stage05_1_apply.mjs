#!/usr/bin/env node
import fs from 'node:fs';
import path from 'node:path';
import { fileURLToPath } from 'node:url';
import { spawnSync } from 'node:child_process';

/**
 * Tah-Lonji Stage 05.1 applier.
 *
 * Usage:
 *   node stage05_1_apply.mjs
 *   node stage05_1_apply.mjs --install
 *
 * Creates backups before overwriting existing files.
 * Does not run database migrations, db push, or database reset.
 */

const __dirname = path.dirname(fileURLToPath(import.meta.url));
const root = fs.realpathSync(__dirname);
const argInstall = process.argv.includes('--install');

const resolve = (p) => path.join(root, ...p.split(/[\\/]/));

const required = [
  'package.json',
  'prisma/schema.prisma',
  'test-db.mts',
  '.gitignore',
];

for (const p of required) {
  const fullPath = resolve(p);

  if (
    !fs.existsSync(fullPath) ||
    !fs.statSync(fullPath).isFile()
  ) {
    console.error(
      `ERROR: Put stage05_1_apply.mjs in the project root, ` +
      `beside package.json and prisma/schema.prisma. Missing: ${p}`,
    );
    process.exit(1);
  }
}

const stamp = new Date()
  .toISOString()
  .replace(/[-:T.Z]/g, '')
  .slice(0, 14);

const backupRoot = resolve(`.stage05.1-backup-${stamp}`);

let backupCreated = false;

const changed = [];
const created = [];
const unchanged = [];

const backedUp = new Set();

function ensureDir(dir) {
  fs.mkdirSync(dir, { recursive: true });
}

function backupFile(rel) {
  const source = resolve(rel);

  if (
    !fs.existsSync(source) ||
    !fs.statSync(source).isFile() ||
    backedUp.has(rel)
  ) {
    return;
  }

  const destination = path.join(
    backupRoot,
    ...rel.split(/[\\/]/),
  );

  ensureDir(path.dirname(destination));
  fs.copyFileSync(source, destination);

  backedUp.add(rel);
  backupCreated = true;
}

function writeManaged(rel, content) {
  const destination = resolve(rel);

  ensureDir(path.dirname(destination));

  if (
    fs.existsSync(destination) &&
    fs.statSync(destination).isFile()
  ) {
    const old = fs.readFileSync(destination, 'utf8');

    if (old === content) {
      unchanged.push(rel.replaceAll('\\', '/'));
      return;
    }

    backupFile(rel);
    fs.writeFileSync(destination, content, 'utf8');

    changed.push(rel.replaceAll('\\', '/'));
  } else {
    fs.writeFileSync(destination, content, 'utf8');

    created.push(rel.replaceAll('\\', '/'));
  }
}

function readRequired(rel) {
  try {
    return fs.readFileSync(resolve(rel), 'utf8');
  } catch {
    throw new Error(`Could not read required file: ${rel}`);
  }
}

function fail(message) {
  console.error(`\nERROR: ${message}`);
  process.exit(1);
}

// ---------------------------------------------------------
// 1. Configure root package.json
// ---------------------------------------------------------

let pkg;

try {
  pkg = JSON.parse(readRequired('package.json'));
} catch {
  fail(
    'Root package.json is not valid JSON. No files have been changed.',
  );
}

pkg.private = true;
pkg.workspaces = ['apps/*'];

pkg.scripts ??= {};

Object.assign(pkg.scripts, {
  'db:generate': 'prisma generate',
  'db:validate': 'prisma validate',
  'db:migrate:status': 'prisma migrate status',

  // Generate Prisma Client after installing dependencies.
  'postinstall': 'prisma generate',

  'api:dev': 'npm run dev --workspace @app/api',
  'api:build':
    'prisma generate && npm run build --workspace @app/api',
  'api:start': 'npm run start --workspace @app/api',
  'api:typecheck': 'npm run typecheck --workspace @app/api',

  'prisma:skills:sync': 'prisma skills sync || exit 0',
});

writeManaged(
  'package.json',
  JSON.stringify(pkg, null, 2) + '\n',
);

// ---------------------------------------------------------
// 2. Update only the Prisma generator output path
// ---------------------------------------------------------

const schema = readRequired('prisma/schema.prisma');

const blocks = [
  ...schema.matchAll(/generator\s+client\s*\{[\s\S]*?\}/g),
];

if (blocks.length !== 1) {
  fail(
    'Expected exactly one generator client block in prisma/schema.prisma.',
  );
}

let changedSchema = schema;
const block = blocks[0][0];

if (!block.includes('../apps/api/src/generated/prisma')) {
  const updatedBlock = block.replace(
    /output\s*=\s*"\.\.\/generated\/prisma"/,
    'output          = "../apps/api/src/generated/prisma"',
  );

  if (updatedBlock === block) {
    fail(
      'Could not safely identify the existing Prisma generator output line.',
    );
  }

  changedSchema = schema.replace(block, updatedBlock);
}

if (changedSchema !== schema) {
  writeManaged('prisma/schema.prisma', changedSchema);
} else {
  unchanged.push('prisma/schema.prisma');
}

// ---------------------------------------------------------
// 3. Update the database test import
// ---------------------------------------------------------

const testDb = readRequired('test-db.mts');

const newImport =
  './apps/api/src/generated/prisma/client';

if (testDb.includes(newImport)) {
  unchanged.push('test-db.mts');
} else {
  const updated = testDb.replace(
    /from\s+(['"])\.\/generated\/prisma\/client\1/,
    `from "${newImport}"`,
  );

  if (updated === testDb) {
    fail(
      'Could not safely update test-db.mts Prisma Client import. ' +
      'Verify the import manually.',
    );
  }

  writeManaged('test-db.mts', updated);
}

// ---------------------------------------------------------
// 4. Update .gitignore without duplicate entries
// ---------------------------------------------------------

let gi = readRequired('.gitignore');

const neededIgnore = [
  'apps/api/dist/',
  'apps/api/src/generated/',
  'apps/api/.env',
  '.stage05.1-backup-*/',
];

const lines = gi.split(/\r?\n/);

const toAppend = neededIgnore.filter(
  (line) => !lines.includes(line),
);

if (toAppend.length) {
  const updatedGitignore =
    `${gi.replace(/[\r\n]+$/, '')}\n\n` +
    `${toAppend.join('\n')}\n`;

  writeManaged('.gitignore', updatedGitignore);
} else {
  unchanged.push('.gitignore');
}

// ---------------------------------------------------------
// 5. Create or update the Stage 05.1 backend files
// ---------------------------------------------------------

const managedFiles = {
  'apps/api/package.json': `{
  "name": "@app/api",
  "version": "0.1.0",
  "private": true,
  "description": "Tah-Lonji platform API (Stage 05.1 foundation)",
  "scripts": {
    "dev": "nest start --watch",
    "build": "nest build",
    "start": "node dist/main.js",
    "typecheck": "tsc --noEmit -p tsconfig.json",
    "format": "prettier --write \\"src/**/*.ts\\"",
    "test": "echo \\"No tests yet (deferred)\\" && exit 0"
  },
  "dependencies": {
    "@nestjs/common": "^11.0.0",
    "@nestjs/config": "^4.0.0",
    "@nestjs/core": "^11.0.0",
    "@nestjs/platform-express": "^11.0.0",
    "@prisma/adapter-pg": "7.10.0",
    "@prisma/client": "7.10.0",
    "pg": "^8.13.0",
    "reflect-metadata": "^0.2.2",
    "rxjs": "^7.8.1",
    "zod": "^3.24.0"
  },
  "devDependencies": {
    "@nestjs/cli": "^11.0.0",
    "@types/express": "^5.0.0",
    "@types/node": "^22.0.0",
    "@types/pg": "^8.11.0",
    "prettier": "^3.4.0",
    "typescript": "^5.7.0"
  }
}
`,

  'apps/api/tsconfig.json': `{
  "compilerOptions": {
    "module": "commonjs",
    "moduleResolution": "node",
    "target": "ES2022",
    "outDir": "./dist",
    "emitDecoratorMetadata": true,
    "experimentalDecorators": true,
    "esModuleInterop": true,
    "allowSyntheticDefaultImports": true,
    "resolveJsonModule": true,
    "sourceMap": true,
    "incremental": true,
    "skipLibCheck": true,
    "strict": true,
    "forceConsistentCasingInFileNames": true
  },
  "include": ["src/**/*"],
  "exclude": ["node_modules", "dist"]
}
`,

  'apps/api/tsconfig.build.json': `{
  "extends": "./tsconfig.json",
  "exclude": ["node_modules", "dist", "test", "**/*.spec.ts"]
}
`,

  'apps/api/nest-cli.json': `{
  "$schema": "https://json.schemastore.org/nest-cli",
  "sourceRoot": "src",
  "compilerOptions": {
    "deleteOutDir": true
  }
}
`,

  'apps/api/.prettierrc': `{ "singleQuote": true, "trailingComma": "all" }
`,

  'apps/api/.env.example': `# Copy values from your local database configuration.
# Never put real secrets in Git.
DATABASE_URL=

# HTTP port (default 3000)
PORT=3000

# development | test | production
NODE_ENV=development

# Comma-separated allowed CORS origins.
CORS_ORIGIN=
`,

  'apps/api/src/main.ts': `import 'reflect-metadata';
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
    \`API listening on http://localhost:\${port}/api/v1\`,
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
`,

  'apps/api/src/app.module.ts': `import { Module } from '@nestjs/common';
import { ConfigModule } from '@nestjs/config';
import { validate } from './config/env.validation';
import { HealthModule } from './health/health.module';
import { PrismaModule } from './prisma/prisma.module';

@Module({
  imports: [
    // App-local .env first, root .env as a fallback.
    ConfigModule.forRoot({
      isGlobal: true,
      cache: true,
      envFilePath: ['.env', '../../.env'],
      validate,
    }),
    PrismaModule,
    HealthModule,
  ],
})
export class AppModule {}
`,

  'apps/api/src/config/env.validation.ts': `import { z } from 'zod';

const envSchema = z.object({
  NODE_ENV: z
    .enum(['development', 'test', 'production'])
    .default('development'),

  PORT: z.coerce
    .number()
    .int()
    .min(1)
    .max(65535)
    .default(3000),

  DATABASE_URL: z
    .string()
    .min(1)
    .refine((value) => value.startsWith('postgres'), {
      message: 'must be a PostgreSQL connection string',
    }),

  CORS_ORIGIN: z.string().optional(),
});

export type Env = z.infer<typeof envSchema>;

export function validate(
  config: Record<string, unknown>,
): Env {
  const parsed = envSchema.safeParse(config);

  if (!parsed.success) {
    // Do not echo environment values because they may contain secrets.
    const details = parsed.error.issues
      .map(
        (issue) =>
          \`  - \${issue.path.join('.') || '(root)'}: \${issue.message}\`,
      )
      .join('\\n');

    throw new Error(
      \`Environment validation failed:\\n\${details}\`,
    );
  }

  return parsed.data;
}
`,

  'apps/api/src/prisma/prisma-client.ts': `/**
 * Single import boundary for the generated Prisma 7 client.
 * If the generator output path changes, update only this file.
 */
export * from '../generated/prisma/client';
`,

  'apps/api/src/prisma/prisma.service.ts': `import {
  Injectable,
  Logger,
  OnModuleDestroy,
  OnModuleInit,
} from '@nestjs/common';
import { PrismaPg } from '@prisma/adapter-pg';
import { PrismaClient } from './prisma-client';

@Injectable()
export class PrismaService
  extends PrismaClient
  implements OnModuleInit, OnModuleDestroy
{
  private readonly logger = new Logger(PrismaService.name);

  constructor() {
    const connectionString = process.env.DATABASE_URL;

    if (!connectionString) {
      throw new Error('DATABASE_URL is not configured');
    }

    super({
      adapter: new PrismaPg({ connectionString }),
    });
  }

  async onModuleInit(): Promise<void> {
    await this.$connect();
    this.logger.log('Database connection established');
  }

  async onModuleDestroy(): Promise<void> {
    await this.$disconnect();
    this.logger.log('Database connection closed');
  }
}
`,

  'apps/api/src/prisma/prisma.module.ts': `import { Global, Module } from '@nestjs/common';
import { PrismaService } from './prisma.service';

@Global()
@Module({
  providers: [PrismaService],
  exports: [PrismaService],
})
export class PrismaModule {}
`,

  'apps/api/src/health/health.service.ts': `import { Injectable, Logger } from '@nestjs/common';
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
      await this.prisma.$queryRaw\`SELECT 1\`;

      return {
        status: 'up',
        latencyMs: Date.now() - startedAt,
      };
    } catch (error: unknown) {
      // Log details only on the server; never expose DB errors over HTTP.
      this.logger.error(
        \`Database health check failed: \${error instanceof Error ? error.name : 'unknown error'}\`,
        error instanceof Error ? error.stack : undefined,
      );

      return { status: 'down' };
    }
  }
}
`,

  'apps/api/src/health/health.controller.ts': `import {
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
`,

  'apps/api/src/health/health.module.ts': `import { Module } from '@nestjs/common';
import { HealthController } from './health.controller';
import { HealthService } from './health.service';

@Module({
  controllers: [HealthController],
  providers: [HealthService],
})
export class HealthModule {}
`,

  'apps/api/src/common/filters/global-exception.filter.ts': `import {
  ArgumentsHost,
  Catch,
  ExceptionFilter,
  HttpException,
  HttpStatus,
  Logger,
} from '@nestjs/common';
import { randomUUID } from 'node:crypto';
import type { Request, Response } from 'express';

@Catch()
export class GlobalExceptionFilter implements ExceptionFilter {
  private readonly logger = new Logger(GlobalExceptionFilter.name);

  catch(exception: unknown, host: ArgumentsHost): void {
    const context = host.switchToHttp();
    const response = context.getResponse<Response>();
    const request = context.getRequest<Request>();

    const correlationId = randomUUID();
    const requestLine =
      \`\${request.method} \${request.originalUrl ?? request.url}\`;

    if (exception instanceof HttpException) {
      const status = exception.getStatus();

      if (status >= 500) {
        this.logger.error(
          \`[\${correlationId}] HTTP \${status} on \${requestLine}\`,
          exception.stack,
        );

        response.status(status).json({
          statusCode: status,
          message: 'Internal server error',
          correlationId,
        });

        return;
      }

      const body = exception.getResponse();

      this.logger.warn(
        \`[\${correlationId}] HTTP \${status} on \${requestLine}\`,
      );

      response.status(status).json(
        typeof body === 'string'
          ? {
              statusCode: status,
              message: body,
              correlationId,
            }
          : {
              ...(body as Record<string, unknown>),
              correlationId,
            },
      );

      return;
    }

    const name =
      exception instanceof Error ? exception.name : 'UnknownError';

    this.logger.error(
      \`[\${correlationId}] Unhandled \${name} on \${requestLine}\`,
      exception instanceof Error ? exception.stack : undefined,
    );

    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
      correlationId,
    });
  }
}
`,
};

// Write the managed backend files.
for (const [rel, contents] of Object.entries(managedFiles)) {
  writeManaged(rel, contents);
}

// ---------------------------------------------------------
// 6. Report file changes
// ---------------------------------------------------------

console.log('\nStage 05.1 file changes applied.');

if (backupCreated) {
  console.log(
    `Backup directory: ${path.relative(root, backupRoot)}`,
  );
}

console.log(`Created: ${created.length} file(s)`);
console.log(`Updated: ${changed.length} file(s)`);
console.log(`Already up to date: ${unchanged.length} file(s)`);

if (created.length) {
  console.log('\nNew files:\n - ' + created.join('\n - '));
}

if (changed.length) {
  console.log('\nUpdated files:\n - ' + changed.join('\n - '));
}

console.log(
  '\nSafety: no database migration was executed or modified; ' +
  'the old root generated/ directory was left in place.',
);

if (!argInstall) {
  console.log(
    '\nNext: run `node stage05_1_apply.mjs --install` ' +
    'to install dependencies and run checks.',
  );

  process.exit(0);
}

// Back up package lock files before npm install can rewrite them.
for (const lock of ['package-lock.json', 'npm-shrinkwrap.json']) {
  backupFile(lock);
}

// ---------------------------------------------------------
// 7. Install and verify
// ---------------------------------------------------------

const commands = [
  ['npm', ['install']],
  ['npm', ['run', 'db:validate']],
  ['npm', ['run', 'api:build']],
  ['npm', ['run', 'api:typecheck']],
  ['npm', ['run', 'db:migrate:status']],
  ['npx', ['tsx', 'test-db.mts']],
];

for (const [command, args] of commands) {
  console.log(`\n> ${command} ${args.join(' ')}`);

  const result = spawnSync(
    command,
    args,
    {
      cwd: root,
      stdio: 'inherit',
      shell: process.platform === 'win32',
    },
  );

  if (result.error) {
    fail(
      `Could not start ${command}: ${result.error.message}`,
    );
  }

  if (result.status !== 0) {
    fail(
      `Command failed (exit ${result.status ?? 'unknown'}): ` +
      `${command} ${args.join(' ')}. Fix the error, then rerun the script.`,
    );
  }
}

console.log(
  '\nAll configured install/build/read-only checks completed successfully.',
);

console.log(
  'Start API with `npm run api:dev`, then check ' +
  'http://localhost:3000/api/v1/health.',
);

console.log(
  'Review `git status prisma/migrations` before committing. ' +
  'Root generated/ remains untouched.',
);