import { GenericContractsDeclaration } from "~~/utils/scaffold-eth/contract";

/**
 * BurnEngineV2 on Base
 * Address will be updated after deployment (Phase 4)
 */
const externalContracts = {
  8453: {
    BurnEngineV2: {
      address: "0x022688adcdc24c648f4efba76e42cd16bd0863ab",
      abi: [
        {
          type: "constructor",
          inputs: [
            { name: "_clankerFeeLocker", type: "address", internalType: "address" },
            { name: "_uniswapRouter", type: "address", internalType: "address" },
            { name: "_pool", type: "address", internalType: "address" },
            { name: "_weth", type: "address", internalType: "address" },
            { name: "_tusd", type: "address", internalType: "address" },
          ],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "CHUNK_FACTOR",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "CLANKER_FEE_LOCKER",
          inputs: [],
          outputs: [{ name: "", type: "address" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "DEAD",
          inputs: [],
          outputs: [{ name: "", type: "address" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "DEFAULT_SLIPPAGE_BPS",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "MIN_SWAP_AMOUNT",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "POOL",
          inputs: [],
          outputs: [{ name: "", type: "address" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "POOL_FEE",
          inputs: [],
          outputs: [{ name: "", type: "uint24" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "TUSD",
          inputs: [],
          outputs: [{ name: "", type: "address" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "UNISWAP_ROUTER",
          inputs: [],
          outputs: [{ name: "", type: "address" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "WETH",
          inputs: [],
          outputs: [{ name: "", type: "address" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "cycleCount",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "executeFullCycle",
          inputs: [{ name: "maxSlippageBps", type: "uint256" }],
          outputs: [],
          stateMutability: "nonpayable",
        },
        {
          type: "function",
          name: "getChunkSize",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getCurrentPrice",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "getStatus",
          inputs: [],
          outputs: [
            { name: "_totalBurnedAllTime", type: "uint256" },
            { name: "_lastCycleTimestamp", type: "uint256" },
            { name: "_cycleCount", type: "uint256" },
            { name: "wethBalance", type: "uint256" },
            { name: "tusdBalance", type: "uint256" },
            { name: "wethRemaining", type: "uint256" },
          ],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "lastCycleTimestamp",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "function",
          name: "totalBurnedAllTime",
          inputs: [],
          outputs: [{ name: "", type: "uint256" }],
          stateMutability: "view",
        },
        {
          type: "event",
          name: "CycleExecuted",
          inputs: [
            { name: "wethClaimed", type: "uint256", indexed: false },
            { name: "tusdClaimed", type: "uint256", indexed: false },
            { name: "wethSwapped", type: "uint256", indexed: false },
            { name: "wethRemaining", type: "uint256", indexed: false },
            { name: "tusdFromSwap", type: "uint256", indexed: false },
            { name: "totalTusdBurned", type: "uint256", indexed: false },
            { name: "totalBurnedAllTime", type: "uint256", indexed: false },
            { name: "timestamp", type: "uint256", indexed: false },
          ],
          anonymous: false,
        },
        { type: "error", name: "InvalidPrice", inputs: [] },
        { type: "error", name: "InvalidSlippage", inputs: [] },
        { type: "error", name: "NothingToBurn", inputs: [] },
        { type: "error", name: "ReentrancyGuardReentrantCall", inputs: [] },
        { type: "error", name: "SafeERC20FailedOperation", inputs: [{ name: "token", type: "address" }] },
      ],
    },
  },
} as const;

export default externalContracts satisfies GenericContractsDeclaration;
