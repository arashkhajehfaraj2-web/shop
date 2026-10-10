import "dotenv/config";
import { PrismaPg } from "@prisma/adapter-pg";
import { PrismaClient } from "./generated/prisma/client";

const connectionString = process.env.DATABASE_URL;

if (!connectionString) {
  throw new Error("DATABASE_URL is missing from .env");
}

const adapter = new PrismaPg({ connectionString });
const prisma = new PrismaClient({ adapter });

async function main() {
  const result = await prisma.$queryRaw<
    Array<{ version: string }>
  >`SELECT version() AS version`;

  console.log("Database connection successful!");
  console.log(result[0]?.version);

  const schemas = await prisma.$queryRaw<
    Array<{ schema_name: string }>
  >`
    SELECT schema_name
    FROM information_schema.schemata
    WHERE schema_name = 'catalog'
  `;

  console.log("Catalog schema exists:", schemas.length > 0);
}

main()
  .catch((error) => {
    console.error("Database test failed:", error);
    process.exitCode = 1;
  })
  .finally(async () => {
    await prisma.$disconnect();
  });