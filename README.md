# Dead Man's Switch — Reactive Omni Buildathon, Track 2 "Set It and Forget It"

## The problem, in plain words

Imagine you hold crypto and something happens to you. Nobody else can move
your money, because only your wallet can sign for it. Your family knows the
money is there, but they cannot reach it.

This project fixes that. You lock funds in a vault and name an heir. While
you are alive, you press a button every now and then to say "I'm still here".
If you go quiet for a long time — say 30 days — the money is sent to your
heir automatically. Nobody has to ask a company, a court, or a middleman.
The blockchain does it.

## How it works

There are two contracts, on two different chains:

1. **The vault — `DeadMansVault`, on Base Sepolia.** This is where the money
   sits. It records three things: who the owner is, who the heir is, and how
   many days of silence trigger a release. It also records the time of the
   owner's last activity. The owner proves they are alive by calling
   `ping()` ("I'm alive") or by depositing. Any plain ETH transfer to the
   vault counts as activity too.
2. **The switch — `DeadMansSwitch`, on Reactive's Lasna testnet.** This is
   the watcher. It cannot hold the money; it only watches and, when the time
   comes, tells the vault to pay out.

### The CRON check

Reactive has a built-in clock. Every so many blocks it sends a "tick" event
to contracts that subscribe to it — like an alarm clock. The switch
subscribes to one of these ticks (Cron1000, about every 17 minutes on Lasna)
and also subscribes to **every event from the vault** on Base Sepolia, so it
notices each ping or deposit the moment it happens.

On every tick the switch does one simple check, using plain timestamps:

> `now - lastActivity >= inactivity period?`

- **No** — the owner was active recently. Do nothing.
- **Yes** — the owner has been silent for the full period. Ask the system
  contract to deliver a callback to the vault's `releaseToHeir()`.

### Why the vault checks too

The switch is only a trigger. The vault is the final guard: before it sends
anything, it checks the timestamps itself. If the owner pinged between the
tick and the callback arriving, the vault refuses and nothing moves. So a
mistaken or stale trigger is harmless — the worst it can do is cost a small
callback fee.

The switch also only considers the job done once it sees the vault's
`Released` event come back. If a callback fails for any reason, the next
tick tries again instead of forgetting about it.

### What the switch can and cannot do

- It **cannot** move funds by itself. Only the vault can, and only through
  Reactive's official callback proxy, and only when the timestamps prove the
  owner has been silent.
- It **cannot** be triggered by a stranger: the vault accepts `releaseToHeir`
  only from the callback proxy, and only when the proxy says the request came
  from this exact switch.
- The owner can change the heir or the inactivity period any time before a
  release. After a release the vault is finished — it holds nothing and
  accepts nothing more.

### A note on time

Everything is measured in **timestamps** (wall-clock seconds), not block
numbers. Base Sepolia does not produce blocks at a fixed speed, so counting
blocks would not measure "30 days" fairly. Lasna and Base Sepolia timestamps
are both Unix time, so a few seconds of drift between the chains means
nothing at the scale of days.

## The two contracts

| Contract | Chain | Job |
|---|---|---|
| `DeadMansVault` | Base Sepolia (84532) | Holds the ETH; records heir, period, last activity; `ping()`; `releaseToHeir()` — only via the callback proxy |
| `DeadMansSwitch` | Lasna testnet (5318007) | Subscribes to the CRON tick and to vault events; on each tick checks the silence; requests the release callback |

Key functions:

- **Vault:** `deposit()` (payable, counts as activity), `ping()`, `setHeir()`,
  `setInactivityPeriod()`, `isInactive()`, `releaseToHeir(address)` (proxy
  only), `coverDebt()`.
- **Switch:** `react(LogRecord)` (system contract only), `setVault()`,
  `setInactivityPeriod()`, `coverDebt()`.

## Values used — all from the official docs (dev.reactive.network)

- Lasna testnet: chain ID **5318007**, RPC `https://lasna-rpc.rnk.dev/`,
  explorer `https://lasna.reactscan.net/`, currency lREACT.
- Base Sepolia: chain ID **84532**, RPC `https://sepolia.base.org`,
  explorer `https://sepolia.basescan.org`.
- System contract (Lasna and mainnet): **0x8888888888888888888888888888888888888888**.
- Legacy system contract (emits the Cron events): **0x0000000000000000000000000000000000fffFfF**.
- Base Sepolia callback proxy: **0x476F44b11F5C942c58f4c8E3d0300E5710743585**.
- CRON topics used: Cron1000 `0xe20b31294d84c3661ddc8f423abb9c70310d0cf172aa2714ead78029b325e3f4`
  (~every 1000 blocks, ~17 min). Cron100 and Cron10000 are also defined in
  the contract for faster/slower checks.
- Library: `Reactive-Network/reactive-lib-omni` v0.1.0, vendored under `lib/` so the repo builds with no submodules — the current Omni
  library matching the docs (`AbstractReactive`, `AbstractCallback`,
  `requestCallbackV_1_0`). The older legacy `reactive-lib` v0.2.0 (RVM-style)
  was installed during research and **removed** — it does not match the
  current docs and must not be used.

Docs pages used: Getting Started, Reactive Contracts, Reactive Mainnet /
Lasna Testnet, Callback Contracts, Origins & Destinations, Demos, and the
Cron Demo repo (`Reactive-Network/reactive-smart-contract-demos`,
`src/demos/cron/CronDemo.sol` — note: that demo file is the legacy version;
the contracts here follow the current Omni docs instead).

## Money and fees — read this before deploying

- **Nothing here costs real money.** Both chains are testnets; only test ETH
  and test lREACT are involved.
- The **vault pays for the release callback** in ETH (Reactive bills the
  recipient on the destination chain). Keep a small extra ETH reserve in the
  vault above the inheritance amount, or the vault will end up in debt after
  the release. The vault is single-use, so that debt has no further effect,
  but the reserve is the clean way.
- The **switch pays for its own subscriptions and ticks** in lREACT. Fund it
  with a small amount after deploy.
- **lREACT faucet (from the docs, CONFIRMED LIVE 2026-11-11):** send SepETH
  to Ethereum Sepolia `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434` or Base
  Sepolia `0x2afaFD298b23b62760711756088F75B7409f5967`; **do NOT send more
  than 5 ETH in one transaction (amounts above 5 ETH are lost)**. The docs
  say 1 ETH gives 100 lREACT; live we received 2.625 lREACT for 0.025 ETH
  (105 per ETH).
- **Do not mix mainnet and testnet.** Testnet origin (Lasna) goes only to a
  testnet destination (Base Sepolia).

## Build and test (done — all green)

```bash
cd dead-mans-switch
forge build   # Solc 0.8.29, via foundry.toml
forge test    # 18 tests, 18 passed
```

Tests prove, locally with `vm.warp` standing in for days passing:

- Vault: deposit records activity and balance; a plain transfer counts as
  activity; `ping()` resets the clock; only the owner can ping; release
  reverts before the period; release reverts for anyone except the callback
  proxy; release reverts for the wrong reactive sender; release succeeds
  after the period and pays the heir in full; release works only once; the
  heir and period can be changed before release.
- Switch: `react()` reverts for anyone except the system contract; a vault
  event updates the last-activity time; a tick before the period requests
  nothing; a tick after the period requests exactly one callback to the
  vault on Base Sepolia calling `releaseToHeir(address)`; the vault's
  `Released` event confirms the release and stops further requests; activity
  just before a tick cancels the trigger; only the owner can change the
  vault.

## Deployed — live on testnet (2026-11-11)

Deployer (fresh throwaway wallet, key only in `.env`):
`0x791F80c3425beD85E86202571e276dF5B1339166`. Heir (fresh throwaway):
`0xBDDf45e79f9c3e0D2F0Ec8680519e998Dd44f098`. All funds testnet only.

| Contract | Chain | Address |
|---|---|---|
| `DeadMansSwitch` (main) | Lasna testnet | `0x0804f3B9FF9C0E676d784ce69a6939ad37d434E8` |
| `DeadMansVault` (main) | Base Sepolia | `0x0804f3b9ff9c0e676d784ce69a6939ad37d434e8` |
| `DeadMansSwitch` (demo) | Lasna testnet | `0x5Fa52DE23Aa1A37b14A1232cD32aeCC801E4fAc6` |
| `DeadMansVault` (demo) | Base Sepolia | `0x41E6356D32Eb00a73E92dA3Ed42a9F79E29b90E7` |

Main pair: 30 days, Cron1000, vault holds 0.01 ETH, switch funded with
0.5 lREACT. Demo pair: 120-second period, Cron100, vault held 0.001 ETH.

Key transaction hashes (full list in `DEPLOY_STATUS.md`):
- lREACT mint: `0xd50515470f7f65d35a59003b479a388843a5b48c95b43373293e0c212b772000`
- Bridge Sepolia -> Base Sepolia: `0x66796914bf17a663c9a128cbef06e7b2c53c0e0cc0a0f1c0547499fad46080b0`
- Main switch deploy: `0xe55dabdf6f1583684eb24c6fecff5ee8ac6462a8b87b36cbf0d53f15ba1e7954`
- Main vault deploy: `0x6e1a933a43e51df1902217a6bb0f5432b6e381214082b90a4371cf5a415b43fe`
- Link (SetVault): `0xcd6e573b942af26c6713a6316adaeb378e36ba9a19c4633f24d4c593dd30b421`

### The autonomous trigger, proven live

With the demo pair (120-second period), nobody pressed anything after setup:

1. Lasna Cron100 tick, block 8110701, tx
   `0x6ec7671aa3f46a8c2b8c97c22068d6a110de4c8b43c6b73f820db47b7ef430bd`:
   the switch saw 125 seconds of silence and requested the release callback.
2. Base Sepolia callback, block 57538259, tx
   `0x5f5dee168ed06a393bcaeb35537a5ba8e46875e5d61d65acc4f6c1f7ca7921ae`:
   Reactive's relayer called the vault through the official callback proxy
   and the vault paid the heir.
3. Result: the demo vault released, and the heir received the full
   0.001 ETH. The demo switch then marked itself done on seeing the
   vault's `Released` event.

Env vars are listed in `.env.example`. Never commit a real `.env`.

## Frontend

`frontend/index.html` is a single-page skeleton: connect wallet, set heir /
days / deposit, "Create vault + deposit", "Ping (I'm alive)", and a status
readout (balance, last activity, days silent, released or not). Paste the
deployed addresses into `VAULT_ADDRESS` / `SWITCH_ADDRESS` and the compiled
vault bytecode into `VAULT_BYTECODE` after deploy.

## Still to do

- [x] Confirm the lREACT faucet works as documented — confirmed live
      2026-11-11 (2.625 lREACT for 0.025 SepETH).
- [x] Deploy to Lasna + Base Sepolia (testnet only) — done 2026-11-11.
- [x] Live trigger test — the demo pair fired on its own (see above).
 - [x] Demo video (under 3 minutes) showing the setup, a ping, and the release — demo/dead_mans_switch_demo.mp4 (89 s, 1920x1080), built 2026-11-11, public on YouTube: https://youtu.be/0ywObz8RlZo.
- [ ] Publish the repo on GitHub with an open-source licence.
- [ ] Submit the DoraHacks BUIDL page with the repo, the demo video, and the
      on-chain transaction hashes.
