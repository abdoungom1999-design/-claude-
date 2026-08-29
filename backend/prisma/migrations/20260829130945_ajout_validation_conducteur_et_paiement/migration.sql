-- CreateEnum
CREATE TYPE "StatutPaiement" AS ENUM ('EN_ATTENTE', 'REUSSI', 'ECHOUE');

-- AlterTable
ALTER TABLE "conducteurs" ADD COLUMN     "estValide" BOOLEAN NOT NULL DEFAULT false;

-- CreateTable
CREATE TABLE "paiements" (
    "id" TEXT NOT NULL,
    "courseId" TEXT NOT NULL,
    "provider" "MethodePaiement" NOT NULL,
    "referenceExterne" TEXT NOT NULL,
    "statut" "StatutPaiement" NOT NULL DEFAULT 'EN_ATTENTE',
    "montantFcfa" INTEGER,
    "createdAt" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updatedAt" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "paiements_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE UNIQUE INDEX "paiements_courseId_key" ON "paiements"("courseId");

-- CreateIndex
CREATE INDEX "paiements_referenceExterne_idx" ON "paiements"("referenceExterne");

-- AddForeignKey
ALTER TABLE "paiements" ADD CONSTRAINT "paiements_courseId_fkey" FOREIGN KEY ("courseId") REFERENCES "courses"("id") ON DELETE RESTRICT ON UPDATE CASCADE;

