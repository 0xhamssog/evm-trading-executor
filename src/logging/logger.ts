import pino, { type DestinationStream, type Logger } from "pino";

export interface ExecutionLogFields {
  msg: string;
  operationId: string;
  transactionHash: string;
  router: string;
  tokenIn: string;
  tokenOut: string;
  state: string;
  durationMs: number;
}

export function createLogger(level: string, destination?: DestinationStream): Logger {
  const options = { level, base: undefined, timestamp: false as const };
  return destination ? pino(options, destination) : pino(options);
}

/** Structured execution log. The field set is fixed so secrets cannot be attached by accident. */
export function logExecution(logger: Logger, fields: ExecutionLogFields): void {
  const { msg, ...details } = fields;
  logger.info(details, msg);
}
