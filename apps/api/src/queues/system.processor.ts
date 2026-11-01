import { Logger } from '@nestjs/common';
import {
  OnWorkerEvent,
  Processor,
  WorkerHost,
} from '@nestjs/bullmq';
import { Job } from 'bullmq';

interface TestJobData {
  message: string;
  requestedAt: string;
}

@Processor('system')
export class SystemProcessor extends WorkerHost {
  private readonly logger = new Logger(SystemProcessor.name);

  async process(
    job: Job<TestJobData>,
  ): Promise<{ message: string; processedAt: string }> {
    switch (job.name) {
      case 'connection-smoke-test': {
        this.logger.log(`Processing job: ${job.id}`);

        return {
          message: job.data.message,
          processedAt: new Date().toISOString(),
        };
      }

      default:
        throw new Error(`Unknown job type: ${job.name}`);
    }
  }

  @OnWorkerEvent('completed')
  onCompleted(job: Job): void {
    this.logger.log(`Job ${job.id} completed successfully`);
  }

  @OnWorkerEvent('failed')
  onFailed(job: Job | undefined, error: Error): void {
    this.logger.error(
      `Job ${job?.id ?? 'unknown'} failed: ${error.message}`,
    );
  }
}