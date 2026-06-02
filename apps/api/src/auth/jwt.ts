import { jwtVerify, createRemoteJWKSet, type JWTPayload } from "jose";
import { config } from "../config.js";

export interface FoundryClaims extends JWTPayload {
  sub: string; // user id (dev) or external IdP subject (jwks)
  tenant_id?: string; // active tenant, if encoded in the token
  email?: string;
}

const devKey = new TextEncoder().encode(config.AUTH_DEV_SECRET);

const jwks =
  config.AUTH_MODE === "jwks" && config.AUTH_JWKS_URL
    ? createRemoteJWKSet(new URL(config.AUTH_JWKS_URL))
    : null;

export async function verifyToken(token: string): Promise<FoundryClaims> {
  if (config.AUTH_MODE === "jwks") {
    if (!jwks) throw new Error("AUTH_JWKS_URL not configured");
    const { payload } = await jwtVerify(token, jwks, {
      issuer: config.AUTH_ISSUER,
      audience: config.AUTH_AUDIENCE,
    });
    return payload as FoundryClaims;
  }
  const { payload } = await jwtVerify(token, devKey);
  return payload as FoundryClaims;
}
