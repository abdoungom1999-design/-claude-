-- CreateSchema
CREATE SCHEMA IF NOT EXISTS "public";

-- Active l'extension PostGIS pour les futures requêtes géospatiales
-- (ex: recherche de conducteurs disponibles via ST_DWithin).
CREATE EXTENSION IF NOT EXISTS postgis;

-- CreateEnum
CREATE TYPE "StatutConducteur" AS ENUM ('EN_LIGNE', 'HORS_LIGNE');

-- CreateEnum
CREATE TYPE "TypeCourse" AS ENUM ('PASSAGER', 'COLIS');

-- CreateEnum
CREATE TYPE "StatutCourse" AS ENUM ('EN_ATTENTE', 'ACCEPTEE', 'EN_COURS', 'TERMINEE', 'ANNULEE');

-- CreateEnum
CREATE TYPE "MethodePaiement" AS ENUM ('WAVE', 'ORANGE_MONEY', 'CASH');

-- CreateEnum
CREATE TYPE "AdminRole" AS ENUM ('SUPER_ADMIN', 'SUPPORT');

-- CreateTable
CREATE TABLE "clients" (
    "id" TEXT NOT NULL,
    "nom" TEXT NOT NULL,
    "telephone" TEXT NOT NULL,
    "motDePasseHash" TEXT NOT NULL,
    "preferences" JSONB,
    "refreshTokenHash" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "clients_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "conducteurs" (
    "id" TEXT NOT NULL,
    "nom" TEXT NOT NULL,
    "telephone" TEXT NOT NULL,
    "motDePasseHash" TEXT NOT NULL,
    "vehiculeId" TEXT,
    "statut" "StatutConducteur" NOT NULL DEFAULT 'HORS_LIGNE',
    "latitudeActuelle" DOUBLE PRECISION,
    "longitudeActuelle" DOUBLE PRECISION,
    "derniereMajPosition" TIMESTAMP(3),
    "refreshTokenHash" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "conducteurs_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "admins" (
    "id" TEXT NOT NULL,
    "email" TEXT NOT NULL,
    "passwordHash" TEXT NOT NULL,
    "role" "AdminRole" NOT NULL DEFAULT 'SUPPORT',
    "refreshTokenHash" TEXT,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "admins_pkey" PRIMARY KEY ("id")
);

-- CreateTable
CREATE TABLE "courses" (
    "id" TEXT NOT NULL,
    "clientId" TEXT NOT NULL,
    "conducteurId" TEXT,
    "type" "TypeCourse" NOT NULL,
    "adresseDepart" TEXT NOT NULL,
    "latitudeDepart" DOUBLE PRECISION NOT NULL,
    "longitudeDepart" DOUBLE PRECISION NOT NULL,
    "adresseArrivee" TEXT NOT NULL,
    "latitudeArrivee" DOUBLE PRECISION NOT NULL,
    "longitudeArrivee" DOUBLE PRECISION NOT NULL,
    "distanceKm" DOUBLE PRECISION,
    "dureeEstimeeMin" INTEGER,
    "prixFcfa" INTEGER,
    "statut" "StatutCourse" NOT NULL DEFAULT 'EN_ATTENTE',
    "methodePaiement" "MethodePaiement",
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "courses_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "clients_telephone_key" ON "clients"("telephone");

-- CreateIndex
CREATE UNIQUE INDEX "conducteurs_telephone_key" ON "conducteurs"("telephone");

-- CreateIndex
CREATE UNIQUE INDEX "admins_email_key" ON "admins"("email");

-- CreateIndex
CREATE INDEX "courses_statut_idx" ON "courses"("statut");

-- CreateIndex
CREATE INDEX "courses_conducteurId_idx" ON "courses"("conducteurId");

-- CreateIndex
CREATE INDEX "courses_clientId_idx" ON "courses"("clientId");

-- AddForeignKey
ALTER TABLE "courses" ADD CONSTRAINT "courses_clientId_fkey" FOREIGN KEY ("clientId") REFERENCES "clients"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "courses" ADD CONSTRAINT "courses_conducteurId_fkey" FOREIGN KEY ("conducteurId") REFERENCES "conducteurs"("id") ON DELETE SET NULL ON UPDATE CASCADE;

