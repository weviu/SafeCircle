-- CreateEnum
CREATE TYPE "Attendance" AS ENUM ('PRESENT', 'ABSENT', 'LATE', 'EXCUSED');

-- CreateEnum
CREATE TYPE "Homework" AS ENUM ('DONE', 'PARTIAL', 'NOT_DONE', 'NOT_GIVEN');

-- CreateEnum
CREATE TYPE "Behavior" AS ENUM ('POSITIVE', 'NEUTRAL', 'CONCERN', 'SEVERE');

-- CreateTable
CREATE TABLE "report_entries" (
    "id" TEXT NOT NULL,
    "student_id" TEXT NOT NULL,
    "author_id" TEXT NOT NULL,
    "report_date" DATE NOT NULL,
    "attendance" "Attendance" NOT NULL,
    "homework" "Homework" NOT NULL,
    "behavior" "Behavior" NOT NULL,
    "note" TEXT,
    "flagged" BOOLEAN NOT NULL DEFAULT false,
    "flag_reason" TEXT,
    "created_at" TIMESTAMP(3) NOT NULL DEFAULT CURRENT_TIMESTAMP,
    "updated_at" TIMESTAMP(3) NOT NULL,

    CONSTRAINT "report_entries_pkey" PRIMARY KEY ("id")
);

-- CreateIndex
CREATE INDEX "report_entries_report_date_idx" ON "report_entries"("report_date");

-- CreateIndex
CREATE INDEX "report_entries_author_id_idx" ON "report_entries"("author_id");

-- CreateIndex
CREATE UNIQUE INDEX "report_entries_student_id_author_id_report_date_key" ON "report_entries"("student_id", "author_id", "report_date");

-- AddForeignKey
ALTER TABLE "report_entries" ADD CONSTRAINT "report_entries_student_id_fkey" FOREIGN KEY ("student_id") REFERENCES "students"("id") ON DELETE CASCADE ON UPDATE CASCADE;

-- AddForeignKey
ALTER TABLE "report_entries" ADD CONSTRAINT "report_entries_author_id_fkey" FOREIGN KEY ("author_id") REFERENCES "users"("id") ON DELETE CASCADE ON UPDATE CASCADE;
