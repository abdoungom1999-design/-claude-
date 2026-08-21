import { Body, Controller, Get, Post, UseGuards } from '@nestjs/common';
import { JwtAccessGuard } from '../auth/guards/jwt-access.guard';
import { JwtPayload } from '../auth/types/jwt-payload.type';
import { CurrentUser } from '../common/decorators/current-user.decorator';
import { Roles } from '../common/decorators/roles.decorator';
import { RolesGuard } from '../common/guards/roles.guard';
import { CoursesService } from './courses.service';
import { CreateCourseDto } from './dto/create-course.dto';

@Controller('courses')
@UseGuards(JwtAccessGuard, RolesGuard)
export class CoursesController {
  constructor(private readonly coursesService: CoursesService) {}

  @Post()
  @Roles('CLIENT')
  creer(@CurrentUser() user: JwtPayload, @Body() dto: CreateCourseDto) {
    return this.coursesService.creer(user.sub, dto);
  }

  @Get('mes-courses')
  @Roles('CLIENT')
  mesCoursesClient(@CurrentUser() user: JwtPayload) {
    return this.coursesService.listerPourClient(user.sub);
  }

  @Get('mes-livraisons')
  @Roles('CONDUCTEUR')
  mesCoursesConducteur(@CurrentUser() user: JwtPayload) {
    return this.coursesService.listerPourConducteur(user.sub);
  }
}
