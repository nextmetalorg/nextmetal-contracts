// SPDX-License-Identifier: MIT
pragma solidity ^0.8.30;

import {Script} from "forge-std/Script.sol";
import {NextMetalPreSale} from "../src/NextMetalPreSale.sol";

/// @notice Simple deployment script for the PreSaleNextMetal contract.
/// The script expects the following environment variables:
/// - USDC: address of the USDC token contract
/// - TREASURY: address of the treasury wallet
/// - TOKEN_NAME: ERC20 name of the NextMetalPreSale token
/// - TOKEN_SYMBOL: ERC20 symbol of the NextMetalPreSale token
contract Deploy is Script {
    function run() external {
        address usdc = vm.envAddress("USDC");
        address treasury = vm.envAddress("TREASURY");
        string memory name = vm.envString("TOKEN_NAME");
        string memory symbol = vm.envString("TOKEN_SYMBOL");
        
        vm.startBroadcast();
        new NextMetalPreSale(usdc, treasury, name, symbol);
        vm.stopBroadcast();
    }
}
