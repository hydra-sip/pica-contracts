// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";

contract PasarelaCargasTest is Test {
    event CargaRegistrada(bytes32 indexed referencia, address indexed pagador, uint256 monto);

    PasarelaCargas internal pasarela;

    address internal dueno = makeAddr("dueno");
    address internal pagador = makeAddr("pagador");

    bytes32 internal constant REFERENCIA = keccak256("carga-1");

    function setUp() public {
        pasarela = new PasarelaCargas(dueno);
        vm.deal(pagador, 10 ether);
    }

    function test_cargar_registraElPagoYEmiteElEvento() public {
        vm.expectEmit(true, true, false, true, address(pasarela));
        emit CargaRegistrada(REFERENCIA, pagador, 0.01 ether);

        vm.prank(pagador);
        pasarela.cargar{value: 0.01 ether}(REFERENCIA);

        assertTrue(pasarela.pagada(REFERENCIA));
        assertEq(address(pasarela).balance, 0.01 ether);
        assertEq(pagador.balance, 9.99 ether);
    }

    function test_constructor_dejaAlDuenoIndicado() public view {
        assertEq(pasarela.owner(), dueno);
    }
}
