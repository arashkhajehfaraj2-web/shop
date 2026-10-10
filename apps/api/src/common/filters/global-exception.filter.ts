import {
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
      `${request.method} ${request.originalUrl ?? request.url}`;

    if (exception instanceof HttpException) {
      const status = exception.getStatus();

      if (status >= 500) {
        this.logger.error(
          `[${correlationId}] HTTP ${status} on ${requestLine}`,
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
        `[${correlationId}] HTTP ${status} on ${requestLine}`,
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
      `[${correlationId}] Unhandled ${name} on ${requestLine}`,
      exception instanceof Error ? exception.stack : undefined,
    );

    response.status(HttpStatus.INTERNAL_SERVER_ERROR).json({
      statusCode: HttpStatus.INTERNAL_SERVER_ERROR,
      message: 'Internal server error',
      correlationId,
    });
  }
}
