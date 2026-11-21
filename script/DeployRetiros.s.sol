// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Script} from "forge-std/Script.sol";
import {PasarelaRetiros} from "../src/PasarelaRetiros.sol";

/// @notice Despliega `PasarelaRetiros`. El firmante es `FIRMANTE` (la dirección de la clave con la
/// que firma el back) y es obligatorio. El dueño inicial es `OWNER` si está definida, y si no, la
/// cuenta que despliega.
/// @dev Uso: forge script script/DeployRetiros.s.sol --rpc-url base_sepolia --account deployer
/// --broadcast --verify
contract DeployRetiros is Script {
    function run() external returns (PasarelaRetiros) {
        return desplegar(vm.envOr("OWNER", msg.sender), vm.envAddress("FIRMANTE"));
    }

    function desplegar(address dueno, address firmante) public returns (PasarelaRetiros retiros) {
        vm.startBroadcast();
        retiros = new PasarelaRetiros(dueno, firmante);
        vm.stopBroadcast();
    }
}
