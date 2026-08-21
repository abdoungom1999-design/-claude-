export const REDIS_CLIENT = 'REDIS_CLIENT';

export const REDIS_KEYS = {
  conducteurPosition: (conducteurId: string) =>
    `conducteur:${conducteurId}:position`,
  conducteursGeoIndex: 'conducteurs:geo',
};
