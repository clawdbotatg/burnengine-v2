"use client";

import { useState } from "react";
import { Address } from "@scaffold-ui/components";
import type { NextPage } from "next";
import { formatEther } from "viem";
import { useAccount } from "wagmi";
import { useScaffoldReadContract, useScaffoldWriteContract } from "~~/hooks/scaffold-eth";

const BURN_ENGINE_ADDRESS = "0x0000000000000000000000000000000000000000"; // TODO: Update after deployment

const Home: NextPage = () => {
  const { address: connectedAddress } = useAccount();
  const [showAdvanced, setShowAdvanced] = useState(false);
  const [customSlippage, setCustomSlippage] = useState("300");
  const [isExecuting, setIsExecuting] = useState(false);
  const [isExecutingCustom, setIsExecutingCustom] = useState(false);

  // Read contract data
  const { data: statusData, isLoading: isLoadingStatus } = useScaffoldReadContract({
    contractName: "BurnEngineV2",
    functionName: "getStatus",
    watch: true,
  });

  const { data: chunkSize, isLoading: isLoadingChunk } = useScaffoldReadContract({
    contractName: "BurnEngineV2",
    functionName: "getChunkSize",
    watch: true,
  });

  const { data: currentPrice, isLoading: isLoadingPrice } = useScaffoldReadContract({
    contractName: "BurnEngineV2",
    functionName: "getCurrentPrice",
    watch: true,
  });

  // Write contract hooks
  const { writeContractAsync: executeDefault } = useScaffoldWriteContract("BurnEngineV2");
  const { writeContractAsync: executeCustom } = useScaffoldWriteContract("BurnEngineV2");

  const handleExecuteDefault = async () => {
    setIsExecuting(true);
    try {
      await executeDefault({
        functionName: "executeFullCycle",
        args: [300n],
      });
    } catch (e) {
      console.error("Execute failed:", e);
    } finally {
      setIsExecuting(false);
    }
  };

  const handleExecuteCustomSlippage = async () => {
    const slippageBps = BigInt(customSlippage);
    if (slippageBps === 0n || slippageBps > 10000n) {
      alert("Slippage must be between 1 and 10000 basis points");
      return;
    }
    setIsExecutingCustom(true);
    try {
      await executeCustom({
        functionName: "executeFullCycle",
        args: [slippageBps],
      });
    } catch (e) {
      console.error("Execute with custom slippage failed:", e);
    } finally {
      setIsExecutingCustom(false);
    }
  };

  // Parse status data
  const totalBurned = statusData ? statusData[0] : 0n;
  const lastTimestamp = statusData ? statusData[1] : 0n;
  const cycleCount = statusData ? statusData[2] : 0n;
  const wethRemaining = statusData ? statusData[5] : 0n;

  const formatTimestamp = (ts: bigint) => {
    if (ts === 0n) return "Never";
    return new Date(Number(ts) * 1000).toLocaleString();
  };

  const formatPrice = (price: bigint | undefined) => {
    if (!price) return "...";
    // Price is in 2^96 fixed point for TUSD/WETH ratio
    return formatEther(price);
  };

  return (
    <div className="flex items-center flex-col grow pt-10">
      <div className="px-5 w-full max-w-2xl">
        <h1 className="text-center">
          <span className="block text-4xl font-bold mb-2">🔥 BurnEngine V2</span>
          <span className="block text-lg text-base-content/70">Permissionless ₸USD Burn Hyperstructure</span>
        </h1>

        {/* Contract Address */}
        <div className="flex justify-center mt-4 mb-8">
          <div className="bg-base-200 rounded-xl px-6 py-3 flex items-center gap-2">
            <span className="text-sm font-medium">Contract:</span>
            <Address address={BURN_ENGINE_ADDRESS} />
          </div>
        </div>

        {/* Stats Grid */}
        <div className="grid grid-cols-2 gap-4 mb-8">
          <div className="bg-base-200 rounded-xl p-4">
            <div className="text-sm text-base-content/60">Total ₸USD Burned</div>
            <div className="text-xl font-bold">
              {isLoadingStatus ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                formatEther(totalBurned)
              )}
            </div>
          </div>

          <div className="bg-base-200 rounded-xl p-4">
            <div className="text-sm text-base-content/60">Cycle Count</div>
            <div className="text-xl font-bold">
              {isLoadingStatus ? <span className="loading loading-spinner loading-sm"></span> : cycleCount.toString()}
            </div>
          </div>

          <div className="bg-base-200 rounded-xl p-4">
            <div className="text-sm text-base-content/60">Last Cycle</div>
            <div className="text-lg font-bold">
              {isLoadingStatus ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                formatTimestamp(lastTimestamp)
              )}
            </div>
          </div>

          <div className="bg-base-200 rounded-xl p-4">
            <div className="text-sm text-base-content/60">WETH Remaining</div>
            <div className="text-xl font-bold">
              {isLoadingStatus ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                `${formatEther(wethRemaining)} ETH`
              )}
            </div>
          </div>

          <div className="bg-base-200 rounded-xl p-4">
            <div className="text-sm text-base-content/60">Current Chunk Size</div>
            <div className="text-xl font-bold">
              {isLoadingChunk ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                `${chunkSize ? formatEther(chunkSize) : "0"} ETH`
              )}
            </div>
          </div>

          <div className="bg-base-200 rounded-xl p-4">
            <div className="text-sm text-base-content/60">Current Price</div>
            <div className="text-xl font-bold">
              {isLoadingPrice ? (
                <span className="loading loading-spinner loading-sm"></span>
              ) : (
                `${formatPrice(currentPrice)} ₸USD/ETH`
              )}
            </div>
          </div>
        </div>

        {/* Execute Button */}
        <div className="flex flex-col items-center gap-4 mb-8">
          {!connectedAddress ? (
            <p className="text-base-content/60">Connect wallet to execute burn cycles</p>
          ) : (
            <>
              <button
                className="btn btn-primary btn-lg w-full max-w-md"
                onClick={handleExecuteDefault}
                disabled={isExecuting}
              >
                {isExecuting ? (
                  <>
                    <span className="loading loading-spinner"></span>
                    Executing Burn Cycle...
                  </>
                ) : (
                  "🔥 Execute Burn Cycle (3% slippage)"
                )}
              </button>

              {/* Advanced Toggle */}
              <button className="btn btn-ghost btn-sm" onClick={() => setShowAdvanced(!showAdvanced)}>
                {showAdvanced ? "▲ Hide Advanced" : "▼ Advanced Options"}
              </button>

              {showAdvanced && (
                <div className="bg-base-200 rounded-xl p-4 w-full max-w-md">
                  <label className="label">
                    <span className="label-text">Custom Slippage (basis points)</span>
                    <span className="label-text-alt">{(Number(customSlippage) / 100).toFixed(2)}%</span>
                  </label>
                  <input
                    type="number"
                    className="input input-bordered w-full mb-3"
                    value={customSlippage}
                    onChange={e => setCustomSlippage(e.target.value)}
                    min="1"
                    max="10000"
                    placeholder="300 = 3%"
                  />
                  <button
                    className="btn btn-warning w-full"
                    onClick={handleExecuteCustomSlippage}
                    disabled={isExecutingCustom}
                  >
                    {isExecutingCustom ? (
                      <>
                        <span className="loading loading-spinner"></span>
                        Executing...
                      </>
                    ) : (
                      `⚠️ Execute with ${(Number(customSlippage) / 100).toFixed(2)}% slippage`
                    )}
                  </button>
                </div>
              )}
            </>
          )}
        </div>

        {/* Info */}
        <div className="bg-base-200 rounded-xl p-4 mb-8">
          <h3 className="font-bold mb-2">How it works</h3>
          <ul className="list-disc list-inside text-sm text-base-content/70 space-y-1">
            <li>Claims Clanker LP fees (WETH + ₸USD)</li>
            <li>Swaps WETH → ₸USD in liquidity-aware chunks</li>
            <li>Burns ALL ₸USD to 0xdead</li>
            <li>No owner, no admin, no pause — permissionless hyperstructure</li>
          </ul>
        </div>
      </div>
    </div>
  );
};

export default Home;
