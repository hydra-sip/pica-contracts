// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Deploy} from "../script/Deploy.s.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";

contract DeployTest is Test {
    /// @dev Un solo test toca `OWNER`: las variables de entorno se comparten entre tests que
    /// corren en paralelo.
    function test_run_despliegaConElDuenoDeOwnerOConElDeployer() public {
        Deploy deploy = new Deploy();

        PasarelaCargas sinOwner = deploy.run();
        assertEq(sinOwner.owner(), address(this));
        _verificarQueQuedaLista(sinOwner);

        address dueno = makeAddr("dueno");
        vm.setEnv("OWNER", vm.toString(dueno));
        PasarelaCargas conOwner = deploy.run();
        assertEq(conOwner.owner(), dueno);
        _verificarQueQuedaLista(conOwner);
    }

    function _verificarQueQuedaLista(PasarelaCargas pasarela) internal {
        assertGt(address(pasarela).code.length, 0);
        assertFalse(pasarela.paused());

        address pagador = makeAddr("pagador");
        vm.deal(pagador, 1 ether);
        vm.prank(pagador);
        pasarela.cargar{value: 1 ether}(keccak256("prueba-1"));
        assertTrue(pasarela.pagada(keccak256("prueba-1")));
    }
}
