import { IsNumber, IsOptional, IsString } from 'class-validator';

/**
 * Forme normalisée attendue des webhooks Wave / Orange Money. Les noms de
 * champs exacts des payloads réels seront alignés lors de l'intégration
 * (Phase 4) avec la documentation officielle de chaque prestataire.
 */
export class PaiementWebhookDto {
  @IsString()
  reference: string; // notre Course.id, transmis comme référence marchande

  @IsString()
  transactionId: string; // identifiant de transaction côté prestataire

  @IsString()
  statut: string; // statut brut du prestataire (ex: "success", "failed")

  @IsOptional()
  @IsNumber()
  montantFcfa?: number;
}
