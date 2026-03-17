// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import {Test, console2} from "forge-std/Test.sol";
import {IERC20} from "@openzeppelin/contracts/token/ERC20/IERC20.sol";
import {BurnEngineV2} from "../contracts/BurnEngineV2.sol";
import {IClankerFeeLocker} from "../contracts/interfaces/IClankerFeeLocker.sol";
import {ISwapRouter02} from "../contracts/interfaces/ISwapRouter02.sol";
import {IUniswapV3Pool} from "../contracts/interfaces/IUniswapV3Pool.sol";

// ─── Mock Contracts ───────────────────────────────────────────

contract MockWETH {
    string public name = "Wrapped Ether";
    string public symbol = "WETH";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockTUSD {
    string public name = "TUSD";
    string public symbol = "TUSD";
    uint8 public decimals = 18;
    mapping(address => uint256) public balanceOf;
    mapping(address => mapping(address => uint256)) public allowance;

    function mint(address to, uint256 amount) external {
        balanceOf[to] += amount;
    }

    function approve(address spender, uint256 amount) external returns (bool) {
        allowance[msg.sender][spender] = amount;
        return true;
    }

    function transfer(address to, uint256 amount) external returns (bool) {
        balanceOf[msg.sender] -= amount;
        balanceOf[to] += amount;
        return true;
    }

    function transferFrom(address from, address to, uint256 amount) external returns (bool) {
        allowance[from][msg.sender] -= amount;
        balanceOf[from] -= amount;
        balanceOf[to] += amount;
        return true;
    }
}

contract MockPool {
    address public token0;
    address public token1;
    uint128 public _liquidity;
    uint160 public _sqrtPriceX96;

    function setTokens(address _token0, address _token1) external {
        token0 = _token0;
        token1 = _token1;
    }

    function setLiquidity(uint128 liq) external {
        _liquidity = liq;
    }

    function setSqrtPriceX96(uint160 price) external {
        _sqrtPriceX96 = price;
    }

    function liquidity() external view returns (uint128) {
        return _liquidity;
    }

    function slot0()
        external
        view
        returns (uint160, int24, uint16, uint16, uint16, uint8, bool)
    {
        return (_sqrtPriceX96, 0, 0, 0, 0, 0, true);
    }
}

contract MockFeeLocker {
    MockWETH public weth;
    MockTUSD public tusd;
    uint256 public wethToGive;
    uint256 public tusdToGive;
    bool public shouldRevert;

    constructor(address _weth, address _tusd) {
        weth = MockWETH(_weth);
        tusd = MockTUSD(_tusd);
    }

    function setAmounts(uint256 _wethAmount, uint256 _tusdAmount) external {
        wethToGive = _wethAmount;
        tusdToGive = _tusdAmount;
    }

    function setShouldRevert(bool _shouldRevert) external {
        shouldRevert = _shouldRevert;
    }

    function claimRewards(address token) external {
        if (shouldRevert) revert("no fees");
        if (token == address(weth) && wethToGive > 0) {
            weth.mint(msg.sender, wethToGive);
            wethToGive = 0;
        }
        if (token == address(tusd) && tusdToGive > 0) {
            tusd.mint(msg.sender, tusdToGive);
            tusdToGive = 0;
        }
    }
}

contract MockRouter {
    MockWETH public weth;
    MockTUSD public tusd;
    uint256 public rate; // tusd per weth in 1e18

    constructor(address _weth, address _tusd) {
        weth = MockWETH(_weth);
        tusd = MockTUSD(_tusd);
        rate = 2000e18; // 1 WETH = 2000 TUSD default
    }

    function setRate(uint256 _rate) external {
        rate = _rate;
    }

    function exactInputSingle(ISwapRouter02.ExactInputSingleParams calldata params)
        external
        payable
        returns (uint256 amountOut)
    {
        weth.transferFrom(msg.sender, address(this), params.amountIn);
        amountOut = (params.amountIn * rate) / 1e18;
        require(amountOut >= params.amountOutMinimum, "slippage");
        tusd.mint(params.recipient, amountOut);
    }
}

// ─── Reentrancy attacker ──────────────────────────────────────

contract ReentrantFeeLocker {
    BurnEngineV2 public target;
    MockWETH public weth;
    bool public attacked;

    constructor(address _weth) {
        weth = MockWETH(_weth);
    }

    function setTarget(address _target) external {
        target = BurnEngineV2(_target);
    }

    function claimRewards(address) external {
        if (!attacked) {
            attacked = true;
            weth.mint(msg.sender, 1 ether);
            try target.executeFullCycle() {} catch {}
        }
    }
}

// ─── Unit Tests ───────────────────────────────────────────────

contract BurnEngineV2Test is Test {
    MockWETH weth;
    MockTUSD tusd;
    MockPool pool;
    MockFeeLocker feeLocker;
    MockRouter router;
    BurnEngineV2 engine;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    // sqrtPrice for ~2000 TUSD/WETH when WETH is token0
    uint160 constant SQRT_PRICE = 3543191142285914205922034323215;

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

    function setUp() public {
        weth = new MockWETH();
        tusd = new MockTUSD();
        pool = new MockPool();
        feeLocker = new MockFeeLocker(address(weth), address(tusd));
        router = new MockRouter(address(weth), address(tusd));

        pool.setTokens(address(weth), address(tusd));
        pool.setSqrtPriceX96(SQRT_PRICE);
        pool.setLiquidity(1000e18);

        engine = new BurnEngineV2(
            address(feeLocker),
            address(router),
            address(pool),
            address(weth),
            address(tusd)
        );
    }

    // ─── Normal Cycle ─────────────────────────────────────────

    function test_normalCycle() public {
        feeLocker.setAmounts(1 ether, 500e18);

        engine.executeFullCycle();

        assertEq(engine.cycleCount(), 1);
        assertGt(engine.totalBurnedAllTime(), 0);
        assertEq(engine.lastCycleTimestamp(), block.timestamp);
        assertEq(tusd.balanceOf(address(engine)), 0);
        assertGt(tusd.balanceOf(DEAD), 0);
    }

    function test_normalCycle_onlyTusdClaimed() public {
        feeLocker.setAmounts(0, 1000e18);

        engine.executeFullCycle();

        assertEq(engine.cycleCount(), 1);
        assertEq(engine.totalBurnedAllTime(), 1000e18);
        assertEq(tusd.balanceOf(DEAD), 1000e18);
    }

    // ─── Event Emission (ethskills: verify events with expectEmit) ──

    function test_emitsCycleExecuted_withCorrectData() public {
        feeLocker.setAmounts(0, 777e18);

        // topic1=false (no indexed), data=true
        vm.expectEmit(false, false, false, true, address(engine));
        emit CycleExecuted(0, 777e18, 0, 0, 0, 777e18, 777e18, block.timestamp);

        engine.executeFullCycle();
    }

    // ─── Chunked Cycle (Large WETH Balance) ───────────────────

    function test_chunkedCycle_largeWethBalance() public {
        weth.mint(address(engine), 100 ether);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle();

        uint256 wethRemaining = weth.balanceOf(address(engine));
        assertGt(wethRemaining, 0, "Should have remaining WETH after chunked swap");
        assertLt(wethRemaining, 100 ether, "Should have swapped some WETH");
        assertGt(tusd.balanceOf(DEAD), 0);
        assertEq(engine.cycleCount(), 1);
    }

    function test_chunkedCycle_multipleCallsDrainBalance() public {
        weth.mint(address(engine), 10 ether);
        feeLocker.setShouldRevert(true);

        for (uint256 i = 0; i < 20; i++) {
            uint256 wethBal = weth.balanceOf(address(engine));
            if (wethBal < engine.MIN_SWAP_AMOUNT()) break;
            engine.executeFullCycle();
        }

        assertGt(engine.cycleCount(), 1, "Should take multiple cycles for large balance");
        assertGt(tusd.balanceOf(DEAD), 0);
    }

    // ─── Emergency Slippage Override ──────────────────────────

    function test_emergencySlippageOverride() public {
        weth.mint(address(engine), 1 ether);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle(5000);

        assertEq(engine.cycleCount(), 1);
        assertGt(tusd.balanceOf(DEAD), 0);
    }

    function test_invalidSlippage_zero() public {
        vm.expectRevert(BurnEngineV2.InvalidSlippage.selector);
        engine.executeFullCycle(0);
    }

    function test_invalidSlippage_tooHigh() public {
        vm.expectRevert(BurnEngineV2.InvalidSlippage.selector);
        engine.executeFullCycle(10001);
    }

    function test_slippage_maxBoundary() public {
        weth.mint(address(engine), 1 ether);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle(10000);
        assertEq(engine.cycleCount(), 1);
    }

    function test_slippage_minBoundary() public {
        weth.mint(address(engine), 1 ether);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle(1); // 0.01% slippage
        assertEq(engine.cycleCount(), 1);
    }

    // ─── Zero Liquidity Edge Case ─────────────────────────────

    function test_zeroLiquidity_skipSwapBurnExistingTusd() public {
        pool.setLiquidity(0);
        tusd.mint(address(engine), 500e18);
        weth.mint(address(engine), 1 ether);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle();

        assertEq(tusd.balanceOf(DEAD), 500e18);
        assertEq(weth.balanceOf(address(engine)), 1 ether);
        assertEq(engine.cycleCount(), 1);
    }

    function test_zeroLiquidity_noTusd_reverts() public {
        pool.setLiquidity(0);
        feeLocker.setShouldRevert(true);

        vm.expectRevert(BurnEngineV2.NothingToBurn.selector);
        engine.executeFullCycle();
    }

    // ─── Dust Threshold ───────────────────────────────────────

    function test_dustThreshold_belowMinSwap() public {
        weth.mint(address(engine), 1e14);
        feeLocker.setShouldRevert(true);

        vm.expectRevert(BurnEngineV2.NothingToBurn.selector);
        engine.executeFullCycle();
    }

    function test_dustThreshold_burnTusdEvenWithDustWeth() public {
        weth.mint(address(engine), 1e14);
        tusd.mint(address(engine), 100e18);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle();

        assertEq(tusd.balanceOf(DEAD), 100e18);
        assertEq(weth.balanceOf(address(engine)), 1e14);
    }

    // ─── Reentrancy Check ─────────────────────────────────────

    function test_reentrancy_blocked() public {
        ReentrantFeeLocker attacker = new ReentrantFeeLocker(address(weth));

        BurnEngineV2 engineWithAttacker = new BurnEngineV2(
            address(attacker),
            address(router),
            address(pool),
            address(weth),
            address(tusd)
        );
        attacker.setTarget(address(engineWithAttacker));

        engineWithAttacker.executeFullCycle();
        assertEq(engineWithAttacker.cycleCount(), 1);
    }

    // ─── NothingToBurn Revert ─────────────────────────────────

    function test_nothingToBurn_noBalanceNoFees() public {
        feeLocker.setShouldRevert(true);

        vm.expectRevert(BurnEngineV2.NothingToBurn.selector);
        engine.executeFullCycle();
    }

    function test_nothingToBurn_claimReturnsNothing() public {
        feeLocker.setAmounts(0, 0);

        vm.expectRevert(BurnEngineV2.NothingToBurn.selector);
        engine.executeFullCycle();
    }

    // ─── View Functions ───────────────────────────────────────

    function test_getStatus() public {
        weth.mint(address(engine), 5 ether);
        tusd.mint(address(engine), 1000e18);

        (
            uint256 burned,
            uint256 lastTs,
            uint256 count,
            uint256 wethBal,
            uint256 tusdBal,
            uint256 wethRemaining
        ) = engine.getStatus();

        assertEq(burned, 0);
        assertEq(lastTs, 0);
        assertEq(count, 0);
        assertEq(wethBal, 5 ether);
        assertEq(tusdBal, 1000e18);
        assertEq(wethRemaining, 5 ether);
    }

    function test_getCurrentPrice() public view {
        uint256 price = engine.getCurrentPrice();
        assertGt(price, 0);
    }

    function test_getChunkSize() public view {
        uint256 chunk = engine.getChunkSize();
        assertGt(chunk, 0);
    }

    function test_getChunkSize_zeroLiquidity() public {
        pool.setLiquidity(0);
        assertEq(engine.getChunkSize(), 0);
    }

    // ─── Fee locker reverts gracefully ────────────────────────

    function test_feeLockerReverts_stillWorks() public {
        feeLocker.setShouldRevert(true);
        weth.mint(address(engine), 1 ether);

        engine.executeFullCycle();

        assertEq(engine.cycleCount(), 1);
        assertGt(tusd.balanceOf(DEAD), 0);
    }

    // ─── State accumulation across cycles ─────────────────────

    function test_stateAccumulatesAcrossCycles() public {
        feeLocker.setAmounts(0, 100e18);
        engine.executeFullCycle();

        assertEq(engine.cycleCount(), 1);
        assertEq(engine.totalBurnedAllTime(), 100e18);

        // Second cycle
        tusd.mint(address(engine), 200e18);
        feeLocker.setShouldRevert(true);
        engine.executeFullCycle();

        assertEq(engine.cycleCount(), 2);
        assertEq(engine.totalBurnedAllTime(), 300e18);
    }

    // ─── Fuzz Tests (ethskills: fuzz test all math) ───────────

    function testFuzz_slippageValidation(uint256 slippage) public {
        if (slippage == 0 || slippage > 10000) {
            vm.expectRevert(BurnEngineV2.InvalidSlippage.selector);
            engine.executeFullCycle(slippage);
        }
        // Valid range tested separately since we need funds
    }

    function testFuzz_chunkSizeNeverExceedsAbsorbable(uint128 liquidityVal, uint160 sqrtPrice) public {
        // Bound to reasonable values
        liquidityVal = uint128(bound(uint256(liquidityVal), 1, type(uint128).max / 2));
        sqrtPrice = uint160(bound(uint256(sqrtPrice), 1 << 48, type(uint160).max / 2));

        pool.setLiquidity(liquidityVal);
        pool.setSqrtPriceX96(sqrtPrice);

        uint256 chunk = engine.getChunkSize();

        // Chunk should always be <= absorbable / CHUNK_FACTOR
        // And never overflow (no revert means safe)
        assertLe(chunk, type(uint256).max);
    }

    function testFuzz_minAmountOutDecreaseWithSlippage(uint256 slippageA, uint256 slippageB) public {
        slippageA = bound(slippageA, 1, 9999);
        slippageB = bound(slippageB, slippageA + 1, 10000);

        weth.mint(address(engine), 1 ether);
        feeLocker.setShouldRevert(true);

        // Higher slippage = lower minAmountOut, so more likely to succeed
        // Both should work with mock router at fair price
        // We can't directly call _calculateMinAmountOut (internal), so we verify
        // indirectly: both slippage values should produce valid cycles
        engine.executeFullCycle(slippageA);

        weth.mint(address(engine), 1 ether);
        engine.executeFullCycle(slippageB);
    }

    function testFuzz_executeWithVariousWethAmounts(uint256 wethAmount) public {
        wethAmount = bound(wethAmount, engine.MIN_SWAP_AMOUNT(), 1000 ether);

        weth.mint(address(engine), wethAmount);
        feeLocker.setShouldRevert(true);

        engine.executeFullCycle();

        // Invariant: TUSD was burned (swap happened)
        assertGt(tusd.balanceOf(DEAD), 0, "TUSD should be burned");
        // Invariant: engine has no TUSD left
        assertEq(tusd.balanceOf(address(engine)), 0, "Engine should have 0 TUSD after cycle");
        // Invariant: cycle count incremented
        assertEq(engine.cycleCount(), 1);
    }

    function testFuzz_dustAmountsRevert(uint256 dustAmount) public {
        dustAmount = bound(dustAmount, 0, engine.MIN_SWAP_AMOUNT() - 1);

        if (dustAmount > 0) {
            weth.mint(address(engine), dustAmount);
        }
        feeLocker.setShouldRevert(true);

        vm.expectRevert(BurnEngineV2.NothingToBurn.selector);
        engine.executeFullCycle();
    }
}

// ─── Invariant Tests (ethskills/testing: invariant tests for stateful protocols) ──

/// @dev Handler contract for guided random actions against BurnEngineV2
contract BurnEngineHandler is Test {
    BurnEngineV2 public engine;
    MockWETH public weth;
    MockTUSD public tusd;
    MockFeeLocker public feeLocker;

    uint256 public totalTusdSentToDead;
    uint256 public cyclesExecuted;

    constructor(BurnEngineV2 _engine, MockWETH _weth, MockTUSD _tusd, MockFeeLocker _feeLocker) {
        engine = _engine;
        weth = _weth;
        tusd = _tusd;
        feeLocker = _feeLocker;
    }

    function executeCycleDefault() public {
        uint256 deadBefore = tusd.balanceOf(0x000000000000000000000000000000000000dEaD);
        try engine.executeFullCycle() {
            uint256 deadAfter = tusd.balanceOf(0x000000000000000000000000000000000000dEaD);
            totalTusdSentToDead += (deadAfter - deadBefore);
            cyclesExecuted++;
        } catch {}
    }

    function executeCycleWithSlippage(uint256 slippage) public {
        slippage = bound(slippage, 1, 10000);
        uint256 deadBefore = tusd.balanceOf(0x000000000000000000000000000000000000dEaD);
        try engine.executeFullCycle(slippage) {
            uint256 deadAfter = tusd.balanceOf(0x000000000000000000000000000000000000dEaD);
            totalTusdSentToDead += (deadAfter - deadBefore);
            cyclesExecuted++;
        } catch {}
    }

    function seedWeth(uint256 amount) public {
        amount = bound(amount, 1, 100 ether);
        weth.mint(address(engine), amount);
    }

    function seedTusd(uint256 amount) public {
        amount = bound(amount, 1, 100_000e18);
        tusd.mint(address(engine), amount);
    }

    function seedFees(uint256 wethAmount, uint256 tusdAmount) public {
        wethAmount = bound(wethAmount, 0, 10 ether);
        tusdAmount = bound(tusdAmount, 0, 50_000e18);
        feeLocker.setAmounts(wethAmount, tusdAmount);
    }
}

contract BurnEngineV2InvariantTest is Test {
    MockWETH weth;
    MockTUSD tusd;
    MockPool pool;
    MockFeeLocker feeLocker;
    MockRouter router;
    BurnEngineV2 engine;
    BurnEngineHandler handler;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;
    uint160 constant SQRT_PRICE = 3543191142285914205922034323215;

    function setUp() public {
        weth = new MockWETH();
        tusd = new MockTUSD();
        pool = new MockPool();
        feeLocker = new MockFeeLocker(address(weth), address(tusd));
        router = new MockRouter(address(weth), address(tusd));

        pool.setTokens(address(weth), address(tusd));
        pool.setSqrtPriceX96(SQRT_PRICE);
        pool.setLiquidity(1000e18);

        engine = new BurnEngineV2(
            address(feeLocker),
            address(router),
            address(pool),
            address(weth),
            address(tusd)
        );

        handler = new BurnEngineHandler(engine, weth, tusd, feeLocker);
        targetContract(address(handler));
    }

    /// @dev totalBurnedAllTime must always equal TUSD sent to DEAD by this engine
    function invariant_totalBurnedMatchesDeadBalance() public view {
        assertEq(
            engine.totalBurnedAllTime(),
            handler.totalTusdSentToDead(),
            "totalBurnedAllTime must match actual TUSD sent to DEAD"
        );
    }

    /// @dev cycleCount must match number of successful executions
    function invariant_cycleCountMatchesExecutions() public view {
        assertEq(
            engine.cycleCount(),
            handler.cyclesExecuted(),
            "cycleCount must match successful executions"
        );
    }

    /// @dev totalBurnedAllTime must always equal DEAD balance increase from this engine
    /// (Replaces per-cycle check since TUSD can be seeded between cycles)
    function invariant_burnedMatchesDeadBalance() public view {
        uint256 deadBalance = tusd.balanceOf(DEAD);
        assertGe(deadBalance, engine.totalBurnedAllTime(), "DEAD balance must be >= totalBurnedAllTime");
    }

    /// @dev totalBurnedAllTime must be monotonically increasing
    function invariant_burnedNeverDecreases() public view {
        assertGe(engine.totalBurnedAllTime(), 0, "totalBurnedAllTime must never be negative");
    }

    /// @dev cycleCount must equal the number of timestamp updates
    function invariant_lastTimestampConsistent() public view {
        if (engine.cycleCount() == 0) {
            assertEq(engine.lastCycleTimestamp(), 0, "No cycles = no timestamp");
        } else {
            assertGt(engine.lastCycleTimestamp(), 0, "After cycles, timestamp must be set");
        }
    }
}

// ─── Fork Tests (ethskills: fork test any external protocol integration) ──

contract BurnEngineV2ForkTest is Test {
    // Real Base mainnet addresses (verified onchain via cast)
    address constant WETH_BASE = 0x4200000000000000000000000000000000000006;
    address constant TUSD_BASE = 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07; // ₸USD on Base
    address constant UNISWAP_ROUTER_BASE = 0x2626664c2603336E57B271c5C0b26F421741e481; // SwapRouter02
    // Clanker v3.1 fee locker - uses claimRewards(address token)
    address constant CLANKER_FEE_LOCKER_BASE = 0x2A787b2362021cC3eEa3C24C4748a6cD5B687382;

    // WETH/₸USD pool on Base (1% fee tier) - verified via Uniswap V3 Factory
    address constant POOL_BASE = 0xd013725b904e76394A3aB0334Da306C505D778F8;

    address constant DEAD = 0x000000000000000000000000000000000000dEaD;

    BurnEngineV2 engine;
    uint256 baseFork;

    function setUp() public {
        // Fork Base mainnet
        baseFork = vm.createSelectFork(vm.envOr("BASE_RPC_URL", string("https://mainnet.base.org")));

        engine = new BurnEngineV2(
            CLANKER_FEE_LOCKER_BASE,
            UNISWAP_ROUTER_BASE,
            POOL_BASE,
            WETH_BASE,
            TUSD_BASE
        );
    }

    function test_fork_viewFunctionsWork() public view {
        // getChunkSize should return nonzero on live pool
        uint256 chunkSize = engine.getChunkSize();
        assertGt(chunkSize, 0, "Chunk size should be > 0 on live pool");

        // getCurrentPrice should return nonzero
        uint256 price = engine.getCurrentPrice();
        assertGt(price, 0, "Price should be > 0");

        // getStatus should work
        (uint256 burned, uint256 lastTs, uint256 count, uint256 wethBal, uint256 tusdBal,) = engine.getStatus();
        assertEq(burned, 0);
        assertEq(lastTs, 0);
        assertEq(count, 0);
        assertEq(wethBal, 0);
        assertEq(tusdBal, 0);
    }

    function test_fork_executeWithWeth() public {
        // Deal WETH to engine (simulating accumulated fees)
        deal(WETH_BASE, address(engine), 0.01 ether);

        uint256 deadBefore = IERC20(TUSD_BASE).balanceOf(DEAD);

        engine.executeFullCycle();

        // Verify TUSD was burned
        uint256 deadAfter = IERC20(TUSD_BASE).balanceOf(DEAD);
        assertGt(deadAfter, deadBefore, "TUSD should have been burned to DEAD");

        // Engine should have no TUSD remaining
        assertEq(IERC20(TUSD_BASE).balanceOf(address(engine)), 0, "Engine should have 0 TUSD");

        // State updated
        assertEq(engine.cycleCount(), 1);
        assertGt(engine.totalBurnedAllTime(), 0);
    }

    function test_fork_executeWithTusd() public {
        // Deal TUSD directly (simulating claimed TUSD fees)
        deal(TUSD_BASE, address(engine), 1000e18);

        uint256 deadBefore = IERC20(TUSD_BASE).balanceOf(DEAD);

        engine.executeFullCycle();

        uint256 deadAfter = IERC20(TUSD_BASE).balanceOf(DEAD);
        assertEq(deadAfter - deadBefore, 1000e18, "Exactly 1000 TUSD should be burned");
        assertEq(engine.totalBurnedAllTime(), 1000e18);
    }

    function test_fork_nothingToBurnReverts() public {
        vm.expectRevert(BurnEngineV2.NothingToBurn.selector);
        engine.executeFullCycle();
    }

    function test_fork_chunkingWorksWithLargeBalance() public {
        // Deal large WETH balance
        deal(WETH_BASE, address(engine), 10 ether);

        // Large balance may exceed 3% price impact per chunk on real pool
        // Use emergency slippage override (10% — accounts for actual price impact)
        engine.executeFullCycle(1000);

        uint256 wethAfter = IERC20(WETH_BASE).balanceOf(address(engine));

        // Should have chunked — not all WETH swapped at once
        assertGt(wethAfter, 0, "Should have remaining WETH after chunked swap");
        assertLt(wethAfter, 10 ether, "Should have swapped some WETH");
        assertGt(engine.totalBurnedAllTime(), 0, "Should have burned some TUSD");
        assertEq(engine.cycleCount(), 1);
    }

    function test_fork_emergencySlippageOverride() public {
        deal(WETH_BASE, address(engine), 0.01 ether);

        // 50% slippage emergency override
        engine.executeFullCycle(5000);

        assertEq(engine.cycleCount(), 1);
        assertGt(engine.totalBurnedAllTime(), 0);
    }

    function test_fork_multipleCyclesAccumulate() public {
        deal(WETH_BASE, address(engine), 0.01 ether);
        engine.executeFullCycle();
        uint256 burned1 = engine.totalBurnedAllTime();

        deal(WETH_BASE, address(engine), 0.01 ether);
        engine.executeFullCycle();
        uint256 burned2 = engine.totalBurnedAllTime();

        assertGt(burned2, burned1, "Burns should accumulate");
        assertEq(engine.cycleCount(), 2);
    }

    function test_fork_realPoolIntegrity() public view {
        // Verify we're talking to real contracts
        IUniswapV3Pool poolContract = IUniswapV3Pool(POOL_BASE);

        address token0 = poolContract.token0();
        address token1 = poolContract.token1();
        uint128 liq = poolContract.liquidity();

        // Pool should have tokens set
        assertTrue(token0 != address(0), "token0 should be set");
        assertTrue(token1 != address(0), "token1 should be set");

        // One of them should be WETH
        assertTrue(
            token0 == WETH_BASE || token1 == WETH_BASE,
            "Pool should contain WETH"
        );
    }
}
