// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "./DeployHelpers.s.sol";
import "../contracts/BurnEngineV2.sol";

contract DeployYourContract is ScaffoldETHDeploy {
    // Base mainnet addresses
    address constant CLANKER_FEE_LOCKER = 0xF3622742b1E446D92e45E22923Ef11C2fcD55D68;
    address constant UNISWAP_ROUTER = 0x2626664c2603336E57B271c5C0b26F421741e481;
    address constant POOL = 0xd013725b904e76394A3aB0334Da306C505D778F8;
    address constant WETH = 0x4200000000000000000000000000000000000006;
    address constant TUSD = 0x3d5e487B21E0569048c4D1A60E98C36e1B09DB07;

    function run() external ScaffoldEthDeployerRunner {
        new BurnEngineV2(
            CLANKER_FEE_LOCKER,
            UNISWAP_ROUTER,
            POOL,
            WETH,
            TUSD
        );
    }
}
