import { Module } from '@nestjs/common';
import { PricingModule } from '../pricing/pricing.module';
import { CoursesController } from './courses.controller';
import { CoursesService } from './courses.service';

@Module({
  imports: [PricingModule],
  controllers: [CoursesController],
  providers: [CoursesService],
})
export class CoursesModule {}
