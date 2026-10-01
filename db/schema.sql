-- PostgreSQL shape for a later durable store.
-- The running demo and tests use the in-memory store in src/persistence/memoryStore.ts.
-- Integer token amounts are text so they are not coerced through floating point.

CREATE TABLE trade_intents (
    operation_id text PRIMARY KEY,
    chain_id bigint NOT NULL,
    caller text NOT NULL,
    router text NOT NULL,
    token_in text NOT NULL,
    token_out text NOT NULL,
    amount_in text NOT NULL,
    min_amount_out text NOT NULL,
    quoted_amount_out text,
    deadline text NOT NULL,
    recipient text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE transactions (
    operation_id text PRIMARY KEY REFERENCES trade_intents (operation_id),
    transaction_hash text,
    state text NOT NULL,
    updated_at timestamptz NOT NULL DEFAULT now()
);

CREATE TABLE trade_events (
    chain_id bigint NOT NULL,
    transaction_hash text NOT NULL,
    log_index integer NOT NULL,
    operation_id text NOT NULL,
    router text NOT NULL,
    token_in text NOT NULL,
    token_out text NOT NULL,
    amount_in text NOT NULL,
    amount_out text NOT NULL,
    recipient text NOT NULL,
    block_number text NOT NULL,
    PRIMARY KEY (chain_id, transaction_hash, log_index)
);

CREATE TABLE reconciliation_records (
    id bigserial PRIMARY KEY,
    operation_id text NOT NULL,
    status text NOT NULL,
    canonical_amount_out text,
    detail text NOT NULL,
    created_at timestamptz NOT NULL DEFAULT now()
);
