# Build Plan: BurnEngine V2 — Permissionless ₸USD Burn Hyperstructure

## Overview
Permissionless hyperstructure that claims Clanker LP fees, swaps WETH→₸USD in auto-sized chunks based on pool liquidity, and burns all ₸USD to 0xdead. V2 fixes the permanent fund-lock risk of V1's hardcoded 3% slippage by introducing liquidity-aware auto-chunking and an emergency slippage override. No owner, no admin, no pause, no upgrade.

## Smart Contracts

### BurnEngineV2.sol
**Inherits:** ReentrancyGuard (OpenZeppelin)

**Immutables (same as V1):**
- `CLANKER_FEE_LOCKER` — Clanker fee claim contract
- `UNISWAP_ROUTER` — SwapRouter02 on Base
- `POOL` — Uniswap V3 WETH/₸USD pool
- `WETH` — WETH token
- `TUSD` — ₸USD token
- `DEAD` — 0x000...dEaD

**Constants:**
- `POOL_FEE = 10000` (1% fee tier)
- `DEFAULT_SLIPPAGE_BPS = 300` (3% default slippage)
- `MIN_SWAP_AMOUNT = 1e15` (0.001 WETH — dust threshold, don't waste gas below this)
- `CHUNK_FACTOR = 10` (swap at most 1/10th of what active liquidity can absorb — targets ~1% price impact)

**Storage (same as V1):**
- `totalBurnedAllTime`
- `lastCycleTimestamp`
- `cycleCount`

**Functions:**

```solidity
/// @notice Default: auto-chunk + 3% slippage
function executeFullCycle() external nonReentrant {
    _execute(DEFAULT_SLIPPAGE_BPS);
}

/// @notice Emergency override: auto-chunk + caller-defined slippage
/// @param maxSlippageBps Slippage tolerance in basis points (300 = 3%, 10000 = 100%)
function executeFullCycle(uint256 maxSlippageBps) external nonReentrant {
    if (maxSlippageBps == 0 || maxSlippageBps > 10000) revert InvalidSlippage();
    _execute(maxSlippageBps);
}
```

**Internal `_execute(uint256 maxSlippageBps)`:**
1. Record WETH/TUSD balances before
2. `try/catch` claim WETH and TUSD from ClankerFeeLocker (same as V1)
3. Read `wethBalance = WETH.balanceOf(address(this))`
4. If `wethBalance >= MIN_SWAP_AMOUNT`:
   - Call `_calculateChunkSize()` to get safe swap amount
   - `chunkSize = min(wethBalance, safeChunkSize)`
   - If `chunkSize < MIN_SWAP_AMOUNT`, skip swap (liquidity too thin, don't waste gas)
   - Else: calculate `minAmountOut` from `slot0().sqrtPriceX96` with `maxSlippageBps` applied
   - `forceApprove` router for `chunkSize`
   - `exactInputSingle` with `chunkSize` as `amountIn`
5. Burn ALL TUSD held by contract to 0xdead (if balance > 0)
6. If no TUSD was burned AND no swap happened, revert `NothingToBurn()` (prevent empty gas waste)
7. Update `totalBurnedAllTime`, `lastCycleTimestamp`, `cycleCount++`
8. Emit `CycleExecuted` event

**Internal `_calculateChunkSize()`:**
```solidity
function _calculateChunkSize() internal view returns (uint256) {
    uint128 activeLiquidity = POOL.liquidity();
    if (activeLiquidity == 0) return 0;

    (uint160 sqrtPriceX96,,,,,,) = POOL.slot0();

    address token0 = POOL.token0();
    uint256 absorbable;

    if (token0 == address(WETH)) {
        absorbable = FullMath.mulDiv(uint256(activeLiquidity), 1 << 96, uint256(sqrtPriceX96));
    } else {
        absorbable = FullMath.mulDiv(uint256(activeLiquidity), uint256(sqrtPriceX96), 1 << 96);
    }

    return absorbable / CHUNK_FACTOR;
}
```

**Internal `_calculateMinAmountOut(uint256 amountIn, uint256 maxSlippageBps)`:**
```solidity
function _calculateMinAmountOut(uint256 amountIn, uint256 maxSlippageBps) internal view returns (uint256) {
    (uint160 sqrtPriceX96,,,,,,) = POOL.slot0();
    if (sqrtPriceX96 == 0) revert InvalidPrice();
    address token0 = POOL.token0();
    uint256 sqrtPrice = uint256(sqrtPriceX96);

    uint256 expectedOut;
    if (token0 == address(WETH)) {
        expectedOut = FullMath.mulDiv(amountIn, FullMath.mulDiv(sqrtPrice, sqrtPrice, 1 << 96), 1 << 96);
    } else {
        expectedOut = FullMath.mulDiv(amountIn, 1 << 96, sqrtPrice);
        expectedOut = FullMath.mulDiv(expectedOut, 1 << 96, sqrtPrice);
    }

    return (expectedOut * (10000 - maxSlippageBps)) / 10000;
}
```

**Events:**
```solidity
event CycleExecuted(
    uint256 wethClaimed,
    uint256 tusdClaimed,
    uint256 wethSwapped,
    uint256 wethRemaining,
    uint256 tusdFromSwap,
    uint256 totalTusdBurned,
    uint256 totalBurnedAllTime,
    uint256 timestamp
);
```

**Errors:**
```solidity
error NothingToBurn();
error InvalidPrice();
error InvalidSlippage();
```

**View Functions:**
- `getStatus()` — same as V1 but add `wethRemaining` for transparency
- `getCurrentPrice()` — same as V1
- `getChunkSize()` — public view that returns `_calculateChunkSize()` so bots/UI can preview

### Interfaces (same as V1)
- `IClankerFeeLocker.sol`
- `ISwapRouter02.sol`
- `IUniswapV3Pool.sol`

### Libraries (same as V1)
- `FullMath.sol`

## Frontend
No frontend changes needed — this is a contract-level fix. The existing CLAWD Dashboard can add:
- Display `wethRemaining` from `getStatus()` to show if chunks are queued
- Display `getChunkSize()` to show current safe swap size
- A simple "Execute Burn Cycle" button that calls `executeFullCycle()` with default params
- An advanced toggle that lets the caller set custom `maxSlippageBps` for the emergency override

## Integrations
- **Uniswap V3 Pool** — reads `liquidity()` and `slot0()` for chunk sizing and price reference
- **Uniswap SwapRouter02** — `exactInputSingle` for WETH→₸USD swap (same as V1)
- **ClankerFeeLocker** — fee claims (same as V1)
- **Bot integration** — any keeper bot or EOA can call `executeFullCycle()` with no params for safe default behavior. Bots can call repeatedly to drain large WETH balances across multiple chunks. No special permissions needed.

## Security Notes

1. **Reentrancy:** ReentrancyGuard on both `executeFullCycle` entry points. CEI pattern maintained.
2. **slot0 manipulation:** Small chunks + 3% slippage = economically irrational sandwich on Base. Emergency path bounded by chunk size.
3. **liquidity() manipulation:** CHUNK_FACTOR = 10 provides 10x safety margin. Combined with slippage protection, bounded.
4. **Zero liquidity:** Swap skipped, existing TUSD still burns. WETH sits safely. No revert.
5. **Dust accumulation:** MIN_SWAP_AMOUNT prevents gas waste. Dust swept on future claims.
6. **Walkaway test:** PASSES. No owner, no admin, no pause, no upgrade, no mutable params.
7. **forceApprove:** Exact chunkSize per cycle, not infinite.

## Recommended Stack
- **Contracts:** Solidity 0.8.20 + Foundry
- **L2:** Base
- **Protocols:** Uniswap V3 (SwapRouter02, Pool), ClankerFeeLocker
- **Libraries:** OpenZeppelin (ReentrancyGuard, SafeERC20, IERC20), FullMath
- **RPC:** Alchemy for Base mainnet + fork testing
- **Deployment:** forge script + forge verify-contract on Basescan
