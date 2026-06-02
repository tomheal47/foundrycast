import Fastify from "fastify";
import cors from "@fastify/cors";
import "./types.js";
import { config } from "./config.js";
import authPlugin from "./plugins/auth.js";
import { healthRoutes, meRoutes } from "./routes/health.js";
import { productRoutes } from "./routes/products.js";

const app = Fastify({
  logger: { transport: { target: "pino-pretty" } },
});

await app.register(cors, { origin: true });
await app.register(authPlugin);
await app.register(healthRoutes);
await app.register(meRoutes);
await app.register(productRoutes);

app.listen({ port: config.PORT, host: "0.0.0.0" }).catch((err) => {
  app.log.error(err);
  process.exit(1);
});
