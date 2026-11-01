import {
  Controller,
  NotFoundException,
  Post,
} from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { QueueTestService } from './queue-test.service';

@Controller('queues')
export class QueuesController {
  constructor(
    private readonly queueTest: QueueTestService,
    private readonly config: ConfigService,
  ) {}

  @Post('test')
  async testQueue() {
    if (this.config.get('NODE_ENV') !== 'development') {
      throw new NotFoundException();
    }

    return this.queueTest.enqueueTestJob();
  }
}