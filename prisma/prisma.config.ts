import dotenv from "dotenv";
import path from "node:path";
import { defineConfig } from "prisma/config";

// Load .env from repo root (one level up from prisma/)
dotenv.config({ path: path.resolve(__dirname, "../.env") });

export default defineConfig({
  // Point to this directory for Prisma 7 multi-file schema support
  // Recursively finds schema.prisma + schema/*.prisma
  schema: __dirname,

  migrations: {
    path: path.join(__dirname, "migrations"),
  },
  datasource: {
    url: process.env.DATABASE_URL || "",
  },
});
