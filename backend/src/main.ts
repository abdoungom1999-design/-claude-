import { ValidationPipe } from '@nestjs/common';
import { ConfigService } from '@nestjs/config';
import { NestFactory } from '@nestjs/core';
import { NestExpressApplication } from '@nestjs/platform-express';
import { AppModule } from './app.module';

async function bootstrap() {
  // rawBody: true conserve le corps brut de la requête (req.rawBody) en
  // plus du JSON parsé, nécessaire pour vérifier les signatures HMAC des
  // webhooks de paiement (le JSON re-sérialisé ne correspond pas
  // forcément octet pour octet à ce qui a été signé par le prestataire).
  const app = await NestFactory.create<NestExpressApplication>(AppModule, {
    rawBody: true,
  });
  const configService = app.get(ConfigService);

  app.enableCors();
  app.useGlobalPipes(
    new ValidationPipe({
      whitelist: true,
      forbidNonWhitelisted: true,
      transform: true,
    }),
  );

  await app.listen(configService.get<number>('port')!);
}
bootstrap();
