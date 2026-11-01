import { Module } from '@nestjs/common';
import { BullModule } from '@nestjs/bullmq';
import { QueuesController } from './queues.controller';
import { QueueTestService } from './queue-test.service';
import { SystemProcessor } from './system.processor';

@Module({
  imports: [
    BullModule.registerQueue({
      name: 'system',
    }),
  ],
  controllers: [QueuesController],
  providers: [
    QueueTestService,
    SystemProcessor,
  ],
})
export class QueuesModule {}