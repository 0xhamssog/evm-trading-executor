# EVM Trading Executor

This repository demonstrates a reusable Solidity/EVM execution layer for automated trading applications.

It focuses on constrained execution, access control, slippage protection, deadline validation, event-driven state, transaction-state management, and reconciliation.

## Why I Built This

Trading applications often mix strategy, risk, and execution in one place. That makes the onchain boundary hard to audit. This project isolates the execution layer: a caller submits a trade that has already been chosen, and the contract enforces who may trade, which routers and tokens are allowed, and which output and deadline bounds must hold.

## What Problem It Solves

An execution contract that can call any address with arbitrary calldata is the wrong tool under a trading bot. This executor exposes one trade function. It pulls a known token, approves one allowlisted router for that call, checks what the recipient actually received, emits a structured event, and clears the allowance before returning.

The TypeScript side treats that event as the canonical fill. A quote is not assumed to equal the amount that landed.

## Architecture

```text
Strategy
   ↓
Risk Engine
   ↓
Trade Intent
   ↓
TypeScript / viem
   ↓
Solidity TradingExecutor
   ↓
Approved Router
   ↓
EVM
   ↓
TradeExecuted
   ↓
Event Decoder
   ↓
Reconciliation
```

Strategy code is intentionally absent. `src/risk/engine.ts` accepts or rejects an intent before anything is signed. `src/execution/executor.ts` encodes, submits, and tracks that intent. The contract does not know why the trade was requested.

## Smart Contract

`contracts/src/TradingExecutor.sol` is a non-upgradeable executor.

Roles:

- `ADMIN` configures routers, tokens, pause, and the executor address. Admin transfer is two-step.
- `EXECUTOR` may call `executeTrade`. That role cannot change allowlists, pause state, or its own authorization.

`executeTrade` checks, in order: caller, pause, reentrancy, operation id, router allowlist, token allowlist, amount, identical tokens, recipient, and deadline. It then pulls `tokenIn` from the caller, swaps through `ITradingRouter`, and pays `recipient`.

`ITradingRouter.swap` is a project interface used by the tests and by future adapters. It is not a universal DEX interface.

Approval model:

```text
Token
 ↓
Approved Router
 ↓
Specific Execution
```

The authorized caller approves the executor for `amountIn`. The executor approves the allowlisted router for that same amount, calls `swap`, then sets the router allowance back to zero. If the token rejects a non-zero allowance overwrite, the executor resets to zero and retries, following the OpenZeppelin `SafeERC20.forceApprove` sequence. Tokens that deliver a different amount than requested are rejected. The recipient's `tokenOut` balance increase is the canonical output. It must match the router's report and be at least `minAmountOut`.

A successful trade consumes its `operationId`. A reverted trade does not, so the same id can be retried after a revert. The TypeScript client still does not resubmit automatically.

## Execution Flow

```text
Authorized Caller
      ↓
Trade Validation
      ↓
Allowed Router
      ↓
Allowed Token
      ↓
Amount Validation
      ↓
Slippage Protection
      ↓
Deadline Validation
      ↓
Execution
      ↓
Trade Event
```

Offchain, an operation id is `keccak256(abi.encodePacked("trade", wallet, sequence))`. That id is the join key from the intent to `TradeExecuted`.

## Security Boundaries

- Only the executor address can trade.
- Only the admin can change configuration.
- Unknown routers and tokens revert.
- `amountIn` and `minAmountOut` must be non-zero.
- `block.timestamp` must be less than or equal to `deadline`.
- Output is measured on the recipient, not taken from an untrusted report alone.
- There is no `call(address target, bytes data)` for arbitrary targets.
- The contract does not custody idle inventory: leftovers of `tokenIn` are returned to the caller in the same transaction.
- Reentrancy into `executeTrade` reverts.

The allowlisted router is trusted to pull up to the approved input for that call. The admin is trusted to maintain the allowlists. Those are explicit trust assumptions, not hidden ones.

## Security Considerations

- restricted callers
- router allowlist
- token allowlist
- slippage validation
- deadline validation
- pause control
- explicit external call boundaries
- no arbitrary target execution
- no private key storage
- deterministic tests

This repository is a technical demonstration and should undergo independent security review before controlling meaningful funds.

## Testing Strategy

The Foundry suite is 60 tests: 46 unit, 9 fuzz, 4 invariants in one campaign, 3 integration, and 1 fork-harness test. Vitest adds 24 tests. Foundry covers the contract. Vitest covers the TypeScript state machine, decoder, reconciliation, and the rule that simulated mode does not broadcast.

| Area | Covered |
|---|---|
| Authorization | Yes |
| Router Allowlist | Yes |
| Token Allowlist | Yes |
| Pause | Yes |
| Deadline | Yes |
| Slippage | Yes |
| External Revert | Yes |
| Events | Yes |
| Fuzzing | Yes |
| Invariants | Yes |
| Integration | Yes |
| Fork Framework | Yes |
| Reconciliation | Yes |

Failure paths covered by the Foundry suite:

- unauthorized caller
- wrong router
- wrong token
- zero amount
- expired trade
- bad slippage
- paused
- router revert
- invalid recipient

Also covered: a router report that does not match the delivered balance, reentrancy, ERC-20 calls that omit a boolean, ERC-20 calls that return false, bubbled token reverts, and a non-zero allowance that must be reset before it can be changed.

## Unit Tests

Unit tests live in `contracts/test/unit`. They use `MockERC20` and `MockTradingRouter`. Time is moved with `vm.warp`. No test waits on a real clock.

## Fuzz Tests

`contracts/test/fuzz/TradingExecutorFuzz.t.sol` checks properties, including:

- `amountIn == 0` always reverts
- `minAmountOut == 0` always reverts
- a deadline before `block.timestamp` always reverts
- `amountOut < minAmountOut` always reverts
- `amountOut >= minAmountOut` succeeds for bounded values
- a caller other than the executor always reverts
- an unknown router or token always reverts

## Invariants

`contracts/test/invariant` runs a handler for 64 sequences. After each call:

- while trading is paused, no trade succeeds
- a non-admin cannot change the router allowlist
- a non-admin cannot change the token allowlist
- the executor role cannot replace itself or unpause

## Integration Tests

`contracts/test/integration` runs the executor, mock router, and mock tokens together. The tests check balances, the refund when a router pulls less than `amountIn`, the cleared router allowance, and that a slippage revert leaves balances unchanged.

## Fork Tests

`contracts/test/fork/ForkFramework.t.sol` reads `FORK_RPC_URL`. When it is empty, the test returns without forking. When it is set, the test selects that endpoint and checks that a chain id and block number are available.

No protocol address is hardcoded. A fork test against a live router should be added only after that router's ABI and deployment are verified for the target chain.

## TypeScript Integration

The client is built with strict TypeScript, viem, Zod, and Pino.

- `src/risk/engine.ts` checks caller, pause, allowlists, amounts, and deadline.
- `src/execution/executor.ts` encodes `executeTrade`, tracks state, waits for a receipt, and decodes the event.
- `src/events/decoder.ts` turns `TradeExecuted` into a `TradeResult`. Amounts are decimal strings.
- `src/reconciliation/reconcile.ts` compares the local record, the receipt, and the event.
- `src/persistence/memoryStore.ts` is the running store. `db/schema.sql` is the PostgreSQL shape for a later adapter. Amounts are `text` so they are not stored as floating-point numbers.

`EXECUTION_MODE` defaults to `SIMULATED`. `submit` throws unless the mode is `TESTNET`. A signing account is injected by the host. This repository does not read a key.

## Transaction State Machine

```text
CREATED
 ↓
SIGNED
 ↓
SUBMITTED
 ↓
PENDING
 ↓
CONFIRMED
```

Failure before a hash exists:

```text
SIGNED
 ↓
FAILED
```

Unknown outcome after broadcast:

```text
SUBMITTED
 ↓
UNKNOWN
```

Recovery:

```text
UNKNOWN
 ↓
RECONCILE
 ↓
CONFIRMED / FAILED / PENDING
```

An RPC timeout moves the record to `UNKNOWN`. The client does not send that operation again. A second `submit` for the same operation id throws. `reconcileSubmitted` applies a later receipt without calling `send`.

## Reconciliation

The canonical output is `TradeExecuted.amountOut`.

```text
requested amountIn: 1000
quoted amountOut:   1000
actual amountOut:   970
canonical result:   970
status:             SYNCED
```

Those figures are the simulated demo fixture, not a market fill.

`SYNCED` means the local record, receipt, and event agree, or a revert is consistently recorded. `MISMATCH` means they disagree, including a balance change that does not equal `amountOut`. `UNKNOWN` means the receipt or the event is missing.

The same log is stored once. The identity is `chainId + transactionHash + logIndex`.

## Running Locally

Install [Foundry](https://book.getfoundry.sh/getting-started/installation) and Node.js 22 or newer. `pnpm` is the package manager.

```bash
git submodule update --init --recursive
pnpm install
forge build
pnpm typecheck
pnpm test
pnpm build
pnpm lint
pnpm demo
```

Foundry:

```bash
forge build
forge test
forge test -vvv
forge coverage
```

```bash
pnpm test:integration
pnpm test:fork
```

`pnpm test` reads `out/TradingExecutor.sol/TradingExecutor.json`, so run `forge build` first.

## Environment Variables

Copy `.env.example`. The demo does not need a filled environment. Invalid configuration throws.

```text
RPC_URL=
FORK_RPC_URL=
CHAIN_ID=31337
EXECUTOR_ADDRESS=
API_PORT=3000
LOG_LEVEL=info
DATABASE_URL=
EXECUTION_MODE=SIMULATED
```

`ADMIN_ADDRESS` and `EXECUTOR_CALLER` are used by `contracts/script/Deploy.s.sol`. The deploy script does not read a signer key. Foundry supplies the signer at broadcast time, outside this repository.

`DATABASE_URL` is accepted and unused. Persistence in this version is in memory.

`EXECUTION_MODE=TESTNET` also requires `RPC_URL` and `EXECUTOR_ADDRESS`. There is no default live-trading path.

## Demo

`pnpm demo` does not broadcast. It prints the checks, a fixture execution, and one structured log line:

```text
EVM Trading Executor
--------------------

Authorization: PASS
Router Allowlist: PASS
Token Allowlist: PASS
Slippage Check: PASS
Deadline Check: PASS
Transaction State: SIMULATED
Event Decode: PASS
Reconciliation: PASS
```

The addresses in that output are fixtures (`0x0000…0002` and the same pattern). `transactionHash` is the label `fixture-not-broadcast`. The operation id is the keccak of the fixture wallet and sequence `1`.

## Project Structure

```text
evm-trading-executor/
├── contracts/
│   ├── src/
│   │   ├── TradingExecutor.sol
│   │   ├── errors/TradingErrors.sol
│   │   ├── interfaces/
│   │   └── libraries/
│   ├── script/Deploy.s.sol
│   └── test/
│       ├── unit/
│       ├── fuzz/
│       ├── invariant/
│       ├── integration/
│       ├── fork/
│       ├── mocks/
│       └── utils/
├── src/
│   ├── abi/
│   ├── clients/evm.ts
│   ├── config/env.ts
│   ├── execution/
│   ├── events/decoder.ts
│   ├── logging/logger.ts
│   ├── persistence/memoryStore.ts
│   ├── reconciliation/
│   ├── risk/engine.ts
│   ├── demo.ts
│   ├── demoFixtures.ts
│   └── index.ts
├── test/typescript/
├── test/fixtures/
├── db/schema.sql
├── foundry.toml
├── package.json
├── Dockerfile
└── README.md
```

## Robinhood Chain Integration

The core contract does not reference Robinhood Chain.

```text
Generic EVM Executor
      ↓
Protocol Adapter
      ↓
Robinhood Chain
```

A future adapter would translate a reviewed Robinhood Chain router into `ITradingRouter`, or sit in front of `executeTrade` and pass an allowlisted router address. Chain id, RPC, and contract addresses stay in configuration.

## Pons Integration

Pons is not implemented here.

```text
Pons Adapter
   ↓
Generic Trade Intent
   ↓
TradingExecutor
```

An adapter should be written against the current official ABI for one Pons version. This repository does not mix Pons versions and does not ship a Pons address.

## Stock Token Integration

```text
Stock Token Adapter
      ↓
Trade Intent
      ↓
Generic Executor
```

Stock token addresses would be configuration for the token allowlist. They are not hardcoded.

## Related Projects

EVM Trading Executor is the generic execution layer. The projects below are separate and specific.

Pons Sniper Bot
https://github.com/0xhamssog/pons-sniper-bot

Pons Sniper is a Pons-specific automated strategy.

Pons Bundler
https://github.com/0xhamssog/pons-bundler

Pons Bundler is multi-wallet launch execution.

Stock Token Arbitrage Bot
https://github.com/0xhamssog/robinhood-stock-token-arbitrage-bot

Stock Token Arbitrage is a Stock Token trading strategy.

## What This Can Become

This executor can serve as the onchain execution layer for:

- trading bots
- arbitrage systems
- copy-trading systems
- multi-wallet applications
- trading terminals
- Robinhood Chain integrations
- Pons integrations
- Stock Token applications
- custom EVM trading infrastructure

## Custom Development

I build custom Solidity/EVM trading infrastructure and connect it to TypeScript backends, risk engines, protocol adapters, and trading applications.

## Roadmap

- Add a protocol adapter only after its ABI and deployment are verified.
- Implement the PostgreSQL store described in `db/schema.sql` behind the same store interface.
- Document a testnet runbook for `EXECUTION_MODE=TESTNET` after a deployment exists.
- Keep strategy, including arbitrage and copy-trading, outside this contract.
