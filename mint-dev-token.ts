/**
 * Mint a dev HS256 token for local testing (AUTH_MODE=dev only).
 * Usage: tsx scripts/mint-dev-token.ts <userId> [tenantId]
 */
import { SignJWT } from "jose";
import { config } from "../src/config.js";

const [, , userId, tenantId] = process.argv;
if (!userId) {
  console.error("usage: mint-dev-token <userId> [tenantId]");
  process.exit(1);
}

const key = new TextEncoder().encode(config.AUTH_DEV_SECRET);
const jwt = new SignJWT({ tenant_id: tenantId })
  .setProtectedHeader({ alg: "HS256" })
  .setSubject(userId)
  .setIssuedAt()
  .setExpirationTime("12h");

console.log(await jwt.sign(key));
