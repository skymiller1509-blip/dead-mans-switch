# Deploy status — 2026-11-11 ~21:40 WAT: DEPLOYED + AUTONOMOUS TRIGGER PROVEN LIVE

## Funding (0.05 SepETH total, Google Cloud Web3 faucet)
- Faucet tx: `0xc5fa70d14c5b819488f7de13b623896d77af7c68389456495042f09fba4e587f`
- Deployer (fresh throwaway, key ONLY in `.env` mode 600, gitignored):
  `0x791F80c3425beD85E86202571e276dF5B1339166`
- Heir (fresh throwaway, key ONLY in `.env`): `0xBDDf45e79f9c3e0D2F0Ec8680519e998Dd44f098`
- lREACT mint: sent 0.025 SepETH to `0x9b9BB25f1A81078C544C829c5EB7822d747Cf434`
  -> received **2.625 lREACT** (105 lREACT per ETH, better than the documented 100).
  Tx: `0xd50515470f7f65d35a59003b479a388843a5b48c95b43373293e0c212b772000`
- Bridge to Base Sepolia: 0.02 SepETH via L1StandardBridge
  `0xfd0Bf71F60660E2f608ed56e1659C450eB113120` (`depositETH`, minGasLimit 200000).
  Tx: `0x66796914bf17a663c9a128cbef06e7b2c53c0e0cc0a0f1c0547499fad46080b0`
  Landed on Base Sepolia after ~10 minutes (slower than the usual 1-3 min;
  the L1 receipt showed the deposit events immediately, the L2 side lagged).
- Sepolia reserve kept: 0.005 SepETH planned; 0.00462 left after gas.

## Main pair (Track 2 entry) — LIVE
- **Switch (Lasna): `0x0804f3B9FF9C0E676d784ce69a6939ad37d434E8`**
  Deploy tx: `0xe55dabdf6f1583684eb24c6fecff5ee8ac6462a8b87b36cbf0d53f15ba1e7954`
  30 days, Cron1000 (~17 min). Funded with 0.5 lREACT.
  Fund tx: `0xb5f4a5f4e3dae7e6858f133cf618961d029999ae737ff1493f5f5b4543559810`
- **Vault (Base Sepolia): `0x0804f3b9ff9c0e676d784ce69a6939ad37d434e8`**
  (same address as the switch — same deployer nonce 0 on both chains)
  Deploy tx: `0x6e1a933a43e51df1902217a6bb0f5432b6e381214082b90a4371cf5a415b43fe`
  Owner = deployer, heir = `0xBDDf...f098`, 30 days, deposit 0.01 ETH.
- **Link tx (SetVault on Lasna):**
  `0xcd6e573b942af26c6713a6316adaeb378e36ba9a19c4633f24d4c593dd30b421`
- Verified on-chain: vault owner/heir/period (2,592,000 s)/balance 0.01 ETH/
  released=false; switch vault/period/balance 0.5 lREACT/released=false.

## Demo pair (separate switch + vault, 120 s period) — RELEASE FIRED ON ITS OWN
- **Demo switch (Lasna): `0x5Fa52DE23Aa1A37b14A1232cD32aeCC801E4fAc6`**
  Deploy tx: `0xb11bae6d6371ecde557e854f988f5bcf9f879266dc47ccb2c32405c7cf2bb63a`
  Cron100 (~2 min), period set to 120 s.
  Fund tx (0.3 lREACT): `0xaa745679e0476eeeac51ceb0e7cfcef7324b662e26114b13174abd5ed1275b06`
- **Demo vault (Base Sepolia): `0x41E6356D32Eb00a73E92dA3Ed42a9F79E29b90E7`**
  Deploy tx: `0x792ea5cb5ff4d8bdaaa9fc5daed683886eee8a0fa96d2a37128eed4d798c61e6`
  Deposit 0.001 ETH, period set to 120 s.
- **Demo link tx (SetVault):**
  `0xd49c9a3213ad6134d644ad062ab43a8f02e975f3dcb10e461626d20af271f71a`
- **Period txs (120 s on both):**
  vault `0xec28d5ffef27d20337e49cca7a0f16f5ddeef95b58b6a04a65ce5a06eb0ef0a8`,
  switch `0x17a61ab667cb6a6807ab49622ba6bbc1c4379a9bdfb392a36c2d5fb532410213`

### The autonomous loop, proven with no manual call
1. Lasna Cron100 tick, block 8110701, tx
   `0x6ec7671aa3f46a8c2b8c97c22068d6a110de4c8b43c6b73f820db47b7ef430bd`:
   the switch's `react()` saw 125 s of silence (>= 120 s period) and emitted
   `ReleaseRequested`. (An earlier tick at block 8110601 correctly did
   nothing: the period was still 1 day then.)
2. Base Sepolia callback, block 57538259, tx
   `0x5f5dee168ed06a393bcaeb35537a5ba8e46875e5d61d65acc4f6c1f7ca7921ae`:
   Reactive relayer -> official callback proxy
   `0x476F44b11F5C942c58f4c8E3d0300E5710743585` -> vault `releaseToHeir()`;
   `Released` event emitted.
3. Result: demo vault `released=true`, balance 0; **heir received the full
   0.001 ETH**; demo switch `released=true` (it saw the Released event).
   Observed: not released at 20:38:04 UTC, released at 20:39:06 UTC.

## Final balances (2026-11-11 ~21:40 WAT)
- Deployer: Sepolia 0.00462 ETH | Base Sepolia 0.00899 ETH | Lasna 1.52007 lREACT
- Main vault 0.01 ETH | main switch 0.5 lREACT
- Demo vault 0 ETH (released) | demo switch 0.24778 lREACT
- Heir 0.001 ETH (the demo release)

## Still to do
 - [x] Demo video (under 3 minutes) — done 2026-11-11, public: https://youtu.be/0ywObz8RlZo.
- [ ] Publish the repo on GitHub with an open-source licence.
 - [ ] Submit the DoraHacks page with the repo, the demo video, and the tx hashes (draft ready in SUBMISSION_DRAFT.md).
- [ ] Frontend: paste the deployed main addresses (done in `frontend/index.html`).

## Notes
- The main switch was NEVER re-pointed at the demo vault; the demo pair is
  fully separate. The main pair is untouched and still armed (30 days).
- Nothing on mainnet, nothing real spent. All funds are testnet only.
