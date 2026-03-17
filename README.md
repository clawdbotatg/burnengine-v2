# 🔥 BurnEngine V2

Permissionless hyperstructure that claims Clanker LP fees, swaps WETH→₸USD in liquidity-aware chunks, and burns all ₸USD to `0xdead`.

V2 fixes the permanent fund-lock risk of V1's hardcoded 3% slippage by introducing **auto-chunking** based on real pool liquidity and an **emergency slippage override** so funds are never stuck.

**No owner. No admin. No pause. No upgrade. Walkaway-safe.**

## Live

- **Contract:** [`0x022688adcdc24c648f4efba76e42cd16bd0863ab`](https://basescan.org/address/0x022688adcdc24c648f4efba76e42cd16bd0863ab) (Base mainnet, Basescan verified)
- **App:** [https://community.bgipfs.com/ipfs/bafybeig53oa3qwpvrgmu6ctww4i7beewghznk5ck3jovk7kddtzirdiumm/](https://community.bgipfs.com/ipfs/bafybeig53oa3qwpvrgmu6ctww4i7beewghznk5ck3jovk7kddtzirdiumm/)
- **Deployer:** `0x472C382550780cD30e1D27155b96Fa4b63d9247e` (clawdheart.eth)

## How It Works

```
Clanker LP Fees → claim WETH + ₸USD → auto-chunk swap WETH→₸USD → burn ALL ₸USD to 0xdead
```

1. **Claim** — pulls accrued WETH and ₸USD fees from ClankerFeeLocker
2. **Chunk** — reads Uniswap V3 pool `liquidity()` to calculate a safe swap size (1/10th of what active liquidity can absorb)
3. **Swap** — executes `exactInputSingle` for the chunk amount with slippage protection
4. **Burn** — transfers all ₸USD in the contract to `0xdead`

Anyone can call `executeFullCycle()`. No permissions needed. Bots can call repeatedly to drain large WETH balances across multiple chunks.

## V1 → V2 Changes

| | V1 | V2 |
|---|---|---|
| **Swap size** | Full WETH balance | Liquidity-aware chunk (1/10th absorbable) |
| **Slippage** | Hardcoded 3% | 3% default + caller-defined override |
| **Fund lock risk** | Yes — large balance + thin liquidity = permanent revert | No — chunks adapt to liquidity, emergency override available |
| **Leftover WETH** | N/A | Tracked via `wethRemaining` in events + `getStatus()` |

## Usage

### Default (recommended)
```solidity
burnEngine.executeFullCycle();
// Auto-chunks + 3% slippage. Safe for bots and EOAs.
```

### Emergency override
```solidity
burnEngine.executeFullCycle(500); // 5% slippage
burnEngine.executeFullCycle(1000); // 10% slippage
// Use when default slippage is too tight for current market conditions.
```

### View functions
```solidity
burnEngine.getStatus();      // totalBurned, cycleCount, wethRemaining, etc.
burnEngine.getChunkSize();   // Preview current safe swap size
burnEngine.getCurrentPrice(); // Current pool price
```

## Contracts

| Contract | Description |
|---|---|
| `BurnEngineV2.sol` | Core burn engine with auto-chunking |
| `IClankerFeeLocker.sol` | Interface for Clanker fee claims |
| `ISwapRouter02.sol` | Uniswap SwapRouter02 interface |
| `IUniswapV3Pool.sol` | Uniswap V3 Pool interface |
| `FullMath.sol` | Safe math for Uniswap price calculations |

## Security

- **ReentrancyGuard** on all external entry points
- **CEI pattern** — state updates before external interactions
- **forceApprove** with exact amounts per cycle (no infinite approvals)
- **slot0 price oracle** — acceptable for a burn engine where output goes to 0xdead. Small chunks make sandwich attacks economically irrational on Base
- **Liquidity manipulation** — CHUNK_FACTOR = 10 provides 10x safety margin against inflated `liquidity()` reads
- **Zero liquidity** — swap skipped gracefully, existing ₸USD still burns, WETH sits safely
- **Dust threshold** — MIN_SWAP_AMOUNT (0.001 WETH) prevents gas waste on tiny amounts
- **41 tests** — 28 unit, 8 fork (live Base state), 5 invariant

## Stack

- **Solidity** 0.8.20 · **Foundry** · **Scaffold-ETH 2**
- **OpenZeppelin** (ReentrancyGuard, SafeERC20, IERC20)
- **Base L2** · **Uniswap V3**

## Build & Test

```bash
yarn install
cd packages/foundry
forge test -vvv

# Fork tests against live Base state
forge test --fork-url $BASE_RPC -vvv
```

## License

MIT
