// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Script} from "forge-std/Script.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";

/// @notice Despliega `PasarelaCargas`. El dueño inicial es `OWNER` si está definida, y si no, la
/// cuenta que despliega.
/// @dev Uso: forge script script/Deploy.s.sol --rpc-url base_sepolia --account deployer
/// --broadcast --verify
contract Deploy is Script {
    function run() external returns (PasarelaCargas pasarela) {
        address dueno = vm.envOr("OWNER", msg.sender);

        vm.startBroadcast();
        pasarela = new PasarelaCargas(dueno);
        vm.stopBroadcast();
    }
}
