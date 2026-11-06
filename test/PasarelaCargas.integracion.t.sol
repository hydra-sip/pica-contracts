// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";

/// @dev Destino de una devolución que, al recibirla, intenta pagar una carga con ese mismo ETH.
contract DestinoQueReentraEnCargar {
    PasarelaCargas internal immutable pasarela;
    bytes32 public constant REFERENCIA = keccak256("carga-del-atacante");

    constructor(PasarelaCargas pasarela_) {
        pasarela = pasarela_;
    }

    receive() external payable {
        pasarela.cargar{value: msg.value}(REFERENCIA);
    }
}

contract PasarelaCargasIntegracionTest is Test {
    PasarelaCargas internal pasarela;

    address internal dueno = makeAddr("dueno");
    address internal tesoreria = makeAddr("tesoreria");
    address internal ana = makeAddr("ana");
    address internal bruno = makeAddr("bruno");
    address internal carla = makeAddr("carla");

    function setUp() public {
        pasarela = new PasarelaCargas(dueno);
        vm.deal(ana, 10 ether);
        vm.deal(bruno, 10 ether);
        vm.deal(carla, 10 ether);
    }

    function test_variosPagadoresYRetirosParcialesCuadran() public {
        bytes32 cargaAna = keccak256("carga-ana");
        bytes32 cargaBruno = keccak256("carga-bruno");
        bytes32 otraCargaAna = keccak256("otra-carga-ana");

        vm.prank(ana);
        pasarela.cargar{value: 1 ether}(cargaAna);
        vm.prank(bruno);
        pasarela.cargar{value: 2.5 ether}(cargaBruno);
        vm.prank(ana);
        pasarela.cargar{value: 0.5 ether}(otraCargaAna);

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
        vm.prank(ana);
        pasarela.cargar{value: 1 ether}(keccak256("carga-ana"));

        vm.expectRevert(PasarelaCargas.TransferenciaFallida.selector);
        vm.prank(dueno);
        pasarela.retirar(payable(address(atacante)), 0.5 ether);

        assertFalse(pasarela.pagada(atacante.REFERENCIA()));
        assertEq(address(pasarela).balance, 1 ether);
        assertEq(address(atacante).balance, 0);
    }
}
