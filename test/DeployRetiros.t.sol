// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {DeployRetiros} from "../script/DeployRetiros.s.sol";
import {PasarelaRetiros} from "../src/PasarelaRetiros.sol";

contract DeployRetirosTest is Test {
    /// @dev `run` lee `FIRMANTE` del entorno. `OWNER` no se toca acá: la cambia `Deploy.t.sol`, que
    /// corre en paralelo; el dueño se prueba con `desplegar`.
    function test_run_despliegaConElFirmanteDelEntorno() public {
        (address firmante,) = makeAddrAndKey("firmante");
        vm.setEnv("FIRMANTE", vm.toString(firmante));

        PasarelaRetiros retiros = new DeployRetiros().run();

        assertEq(retiros.firmante(), firmante);
        assertGt(address(retiros).code.length, 0);
    }

    function test_desplegar_dejaLaPasarelaListaParaCobrar() public {
        (address firmante, uint256 clave) = makeAddrAndKey("firmante");
        address dueno = makeAddr("dueno-retiros");

        PasarelaRetiros retiros = new DeployRetiros().desplegar(dueno, firmante);

        assertEq(retiros.owner(), dueno);
        assertEq(retiros.firmante(), firmante);
        assertFalse(retiros.paused());

        vm.deal(address(this), 1 ether);
        (bool ok,) = address(retiros).call{value: 1 ether}("");
        assertTrue(ok);
        address usuario = makeAddr("usuario");
        uint256 vence = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(clave, retiros.digestDelRetiro(keccak256("prueba-1"), usuario, 1 ether, vence));
        vm.prank(usuario);
        retiros.cobrar(keccak256("prueba-1"), 1 ether, vence, abi.encodePacked(r, s, v));
        assertEq(usuario.balance, 1 ether);
    }
}
