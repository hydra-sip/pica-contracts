// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {PasarelaCargas} from "../src/PasarelaCargas.sol";
import {PasarelaRetiros} from "../src/PasarelaRetiros.sol";
import {EscenarioRetiros} from "./utils/EscenarioRetiros.sol";

/// @dev El recorrido completo de la plata en la cadena: los usuarios cargan en `PasarelaCargas`,
/// el dueño pasa lo recaudado a `PasarelaRetiros` y otros usuarios cobran sus retiros.
contract PasarelaRetirosIntegracionTest is EscenarioRetiros {
    PasarelaCargas internal cargas;
    address internal ana = makeAddr("ana");
    address internal bruno = makeAddr("bruno");
    address internal carla = makeAddr("carla");

    function setUp() public override {
        (firmante, claveFirmante) = makeAddrAndKey("firmante");
        retiros = new PasarelaRetiros(dueno, firmante);
        cargas = new PasarelaCargas(dueno);
        vm.deal(ana, 5 ether);
        vm.deal(bruno, 5 ether);
    }

    function test_loRecaudadoEnCargasPagaLosRetirosDeVariosUsuarios() public {
        vm.prank(ana);
        cargas.cargar{value: 2 ether}(keccak256("carga-ana"));
        vm.prank(bruno);
        cargas.cargar{value: 3 ether}(keccak256("carga-bruno"));

        vm.expectEmit(true, false, false, true, address(retiros));
        emit Fondeado(address(cargas), 4 ether);
        vm.prank(dueno);
        cargas.retirar(payable(address(retiros)), 4 ether);

        _cobrar(carla, keccak256("retiro-carla"), 2.5 ether);
        _cobrar(ana, keccak256("retiro-ana"), 1 ether);

        vm.prank(dueno);
        retiros.retirar(payable(tesoreria), 0.5 ether);

        assertEq(ana.balance, 4 ether);
        assertEq(bruno.balance, 2 ether);
        assertEq(carla.balance, 2.5 ether);
        assertEq(tesoreria.balance, 0.5 ether);
        assertEq(address(cargas).balance, 1 ether);
        assertEq(address(retiros).balance, 0);
        assertTrue(retiros.cobrado(keccak256("retiro-carla")));
        assertTrue(retiros.cobrado(keccak256("retiro-ana")));
    }

    function test_unaFirmaFiltradaSeAnulaCambiandoElFirmante() public {
        vm.prank(ana);
        cargas.cargar{value: 3 ether}(keccak256("carga-ana"));
        vm.prank(dueno);
        cargas.retirar(payable(address(retiros)), 3 ether);
        uint256 vence = block.timestamp + 1 hours;
        bytes memory filtrada = _firmar(keccak256("retiro-bruno"), bruno, 3 ether, vence);

        (address nuevo,) = makeAddrAndKey("firmante-nuevo");
        vm.startPrank(dueno);
        retiros.pausar();
        retiros.cambiarFirmante(nuevo);
        retiros.reanudar();
        vm.stopPrank();

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(bruno);
        retiros.cobrar(keccak256("retiro-bruno"), 3 ether, vence, filtrada);

        assertEq(bruno.balance, 5 ether);
        assertEq(address(retiros).balance, 3 ether);
    }
}
