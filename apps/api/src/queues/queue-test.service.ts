import { Injectable } from '@nestjs/common';
import { InjectQueue } from '@nestjs/bullmq';
import { Queue } from 'bullmq';

@Injectable()
export class QueueTestService {
  constructor(
    @InjectQueue('system')
    private readonly systemQueue: Queue,
  ) {}

  async enqueueTestJob() {
    const job = await this.systemQueue.add(
      'connection-smoke-test',
      {
        message: 'Tah-Lonji BullMQ connection is working!',
        requestedAt: new Date().toISOString(),
      },
      {
        attempts: 3,
        backoff: {
          type: 'exponential',
          delay: 1000,
        },
        removeOnComplete: {
          count: 100,
        },
        removeOnFail: {
          count: 500,
        },
      },
    );

    return {
      message: 'Test job queued successfully',
      queue: 'system',
      jobId: job.id,
    };
  }
}