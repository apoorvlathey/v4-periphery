// SPDX-License-Identifier: MIT
pragma solidity ^0.8.20;

import "forge-std/console2.sol";
import "forge-std/Script.sol";

import {Deploy, IV4QuoterV2} from "../test/shared/Deploy.sol";

contract DeployV4QuoterV2 is Script {
    function setUp() public {}

    function run(address poolManager) public returns (IV4QuoterV2 state) {
        vm.startBroadcast();

        // export WALLETCHAN_RPC_URL=http://127.0.0.1:4210
        // export WALLETCHAN_SENDER=$(cast rpc --rpc-url "$WALLETCHAN_RPC_URL" eth_accounts | jq -er '.[0]')
        // forge script script/DeployV4QuoterV2.s.sol:DeployV4QuoterV2 \
        //   --sig 'run(address)' 0x000000000004444c5dc75cB358380D2e3dE08A90 \
        //   --rpc-url "$WALLETCHAN_RPC_URL" --broadcast --unlocked --slow \
        //   --sender "$WALLETCHAN_SENDER" --verify -vvvv
        state = Deploy.v4QuoterV2(poolManager, hex"00");
        console2.log("V4QuoterV2", address(state));
        console2.log("PoolManager", address(state.poolManager()));

        vm.stopBroadcast();
    }
}
