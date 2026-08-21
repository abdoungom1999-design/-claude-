import { Module } from '@nestjs/common';
import { ConducteursController } from './conducteurs.controller';
import { ConducteursService } from './conducteurs.service';

@Module({
  controllers: [ConducteursController],
  providers: [ConducteursService],
})
export class ConducteursModule {}
