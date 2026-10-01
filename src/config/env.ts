import { z } from "zod";

const addressSchema = z.string().regex(/^0x[a-fA-F0-9]{40}$/u, "expected an EVM address");

export const EnvSchema = z.object({
  RPC_URL: z.string().default(""),
  FORK_RPC_URL: z.string().default(""),
  CHAIN_ID: z.coerce.number().int().positive().default(31337),
  EXECUTOR_ADDRESS: z.union([z.literal(""), addressSchema]).default(""),
  ADMIN_ADDRESS: z.union([z.literal(""), addressSchema]).default(""),
  EXECUTOR_CALLER: z.union([z.literal(""), addressSchema]).default(""),
  API_PORT: z.coerce.number().int().positive().max(65535).default(3000),
  LOG_LEVEL: z.enum(["fatal", "error", "warn", "info", "debug", "trace"]).default("info"),
  DATABASE_URL: z.string().default(""),
  EXECUTION_MODE: z.enum(["SIMULATED", "TESTNET"]).default("SIMULATED"),
});

export type AppConfig = z.infer<typeof EnvSchema>;

/** Parse process environment and refuse to start when testnet mode is incomplete. */
export function loadConfig(env: Record<string, string | undefined> = process.env): AppConfig {
  const parsed = EnvSchema.safeParse(env);
  if (!parsed.success) {
    const message = parsed.error.issues.map((issue) => `${issue.path.join(".")}: ${issue.message}`).join("; ");
    throw new Error(`Invalid configuration: ${message}`);
  }

  const config = parsed.data;
  if (config.EXECUTION_MODE === "TESTNET") {
    if (config.RPC_URL.length === 0) {
      throw new Error("Invalid configuration: RPC_URL is required when EXECUTION_MODE=TESTNET");
    }
    if (config.EXECUTOR_ADDRESS.length === 0) {
      throw new Error("Invalid configuration: EXECUTOR_ADDRESS is required when EXECUTION_MODE=TESTNET");
    }
  }
  return config;
}
