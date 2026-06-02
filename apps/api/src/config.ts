import { z } from "zod";

const Env = z.object({
  PORT: z.coerce.number().default(3000),
  DATABASE_URL: z
    .string()
    .default("postgresql://foundrycast_app:app@localhost:5432/foundrycast"),

  // 'dev'  -> HS256 tokens signed with AUTH_DEV_SECRET (local only)
  // 'jwks' -> RS256 verified against AUTH_JWKS_URL (Auth0 / Supabase)
  AUTH_MODE: z.enum(["dev", "jwks"]).default("dev"),
  AUTH_DEV_SECRET: z.string().default("dev-only-secret-change-me"),
  AUTH_JWKS_URL: z.string().url().optional(),
  AUTH_ISSUER: z.string().optional(),
  AUTH_AUDIENCE: z.string().optional(),
});

export const config = Env.parse(process.env);
export type Config = typeof config;
