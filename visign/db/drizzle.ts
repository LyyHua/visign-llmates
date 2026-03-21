import { neon } from "@neondatabase/serverless";
import { drizzle } from "drizzle-orm/neon-http";

import * as schema from "./schema";

if (!process.env.DATABASE_URL) {
	throw new Error("Missing required environment variable: DATABASE_URL");
}

const sql = neon(process.env.DATABASE_URL);
const db = drizzle(sql, { schema });

export default db;
