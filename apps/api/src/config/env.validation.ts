import { z } from 'zod';

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
          `  - ${issue.path.join('.') || '(root)'}: ${issue.message}`,
      )
      .join('\n');

    throw new Error(
      `Environment validation failed:\n${details}`,
    );
  }

  return parsed.data;
}
