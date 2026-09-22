# Image de production du backend Sprint (NestJS + Prisma).
# Build multi-étapes : dépendances + compilation dans `builder`, image
# finale allégée pour l'exécution.

FROM node:20-slim AS builder
WORKDIR /app

COPY package.json package-lock.json ./
# --ignore-scripts : à ce stade prisma/schema.prisma n'existe pas encore
# dans l'image (seuls package.json/package-lock.json sont copiés, pour
# profiter du cache Docker), donc le postinstall (prisma generate) doit
# être reporté après la copie complète des sources ci-dessous.
RUN npm ci --ignore-scripts

COPY . .
RUN npx prisma generate
RUN npm run build

FROM node:20-slim AS runtime
WORKDIR /app
ENV NODE_ENV=production

COPY --from=builder /app/node_modules ./node_modules
COPY --from=builder /app/dist ./dist
COPY --from=builder /app/generated ./generated
COPY --from=builder /app/prisma ./prisma
COPY --from=builder /app/prisma.config.ts ./prisma.config.ts
COPY --from=builder /app/package.json ./package.json

# Render/Railway/Fly injectent leur propre PORT ; 3000 sert de valeur par
# défaut pour un lancement local du conteneur.
EXPOSE 3000

# Applique les migrations Prisma (dont l'activation de PostGIS) avant de
# démarrer le serveur, à chaque déploiement.
CMD ["npm", "run", "start:prod"]
