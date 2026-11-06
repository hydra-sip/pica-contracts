// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {PasarelaCargas} from "../src/PasarelaCargas.sol";
import {EscenarioPasarela} from "./utils/EscenarioPasarela.sol";
import {DestinoQueReentraEnCargar} from "./utils/Atacantes.sol";

contract PasarelaCargasIntegracionTest is EscenarioPasarela {
    address internal ana;
    address internal bruno;
    address internal carla;

    function setUp() public override {
        super.setUp();
        ana = _nuevoPagador("ana");
        bruno = _nuevoPagador("bruno");
        carla = _nuevoPagador("carla");
    }

    function test_variosPagadoresYRetirosParcialesCuadran() public {
        bytes32 cargaAna = keccak256("carga-ana");
        bytes32 cargaBruno = keccak256("carga-bruno");
        bytes32 otraCargaAna = keccak256("otra-carga-ana");

        _cargarDesde(ana, cargaAna, 1 ether);
        _cargarDesde(bruno, cargaBruno, 2.5 ether);
        _cargarDesde(ana, otraCargaAna, 0.5 ether);

        vm.startPrank(dueno);
        pasarela.retirar(payable(tesoreria), 3 ether);
        pasarela.retirar(payable(carla), 0.25 ether);
        vm.stopPrank();

        assertTrue(pasarela.pagada(cargaAna));
        assertTrue(pasarela.pagada(cargaBruno));
        assertTrue(pasarela.pagada(otraCargaAna));
        assertFalse(pasarela.pagada(keccak256("carga-carla")));

        assertEq(ana.balance, 8.5 ether);
        assertEq(bruno.balance, 7.5 ether);
        assertEq(carla.balance, 10.25 ether);
        assertEq(tesoreria.balance, 3 ether);
        assertEq(address(pasarela).balance, 0.75 ether);
    }

    function test_unaDevolucionNoPuedeReentrarEnCargar() public {
        DestinoQueReentraEnCargar atacante = new DestinoQueReentraEnCargar(pasarela);
        _cargarDesde(ana, keccak256("carga-ana"), 1 ether);

        vm.expectRevert(PasarelaCargas.TransferenciaFallida.selector);
        vm.prank(dueno);
        pasarela.retirar(payable(address(atacante)), 0.5 ether);

        assertFalse(pasarela.pagada(atacante.REFERENCIA()));
        assertEq(address(pasarela).balance, 1 ether);
        assertEq(address(atacante).balance, 0);
    }
}
