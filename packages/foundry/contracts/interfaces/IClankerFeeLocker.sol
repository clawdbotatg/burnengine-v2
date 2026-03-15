// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

interface IClankerFeeLocker {
    function claimFees(address token0, address token1) external;
}
