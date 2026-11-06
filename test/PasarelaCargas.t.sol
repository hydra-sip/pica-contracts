// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";

/// @dev Destino sin `receive` ni `fallback`: rechaza cualquier ETH.
contract DestinoQueRechazaEth {}

/// @dev Dueño y destino a la vez: al recibir el retiro intenta retirar de nuevo.
contract DuenoQueReentraEnRetirar {
    PasarelaCargas public pasarela;
    uint256 public reentradas;

    function apuntarA(PasarelaCargas pasarela_) external {
        pasarela = pasarela_;
    }

    function retirar(uint256 monto) external {
        pasarela.retirar(payable(address(this)), monto);
    }

    receive() external payable {
        if (address(pasarela).balance >= msg.value) {
            reentradas++;
            pasarela.retirar(payable(address(this)), msg.value);
        }
    }
}

contract PasarelaCargasTest is Test {
    event CargaRegistrada(bytes32 indexed referencia, address indexed pagador, uint256 monto);
    event FondosRetirados(address indexed destino, uint256 monto);

    PasarelaCargas internal pasarela;

    address internal dueno = makeAddr("dueno");
    address internal pagador = makeAddr("pagador");
    address internal tesoreria = makeAddr("tesoreria");

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

    function _cargar(bytes32 referencia, uint256 monto) internal {
        vm.prank(pagador);
        pasarela.cargar{value: monto}(referencia);
    }

    function test_retirar_transfiereElMontoAlDestinoYEmiteElEvento() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectEmit(true, false, false, true, address(pasarela));
        emit FondosRetirados(tesoreria, 0.4 ether);

        vm.prank(dueno);
        pasarela.retirar(payable(tesoreria), 0.4 ether);

        assertEq(tesoreria.balance, 0.4 ether);
        assertEq(address(pasarela).balance, 0.6 ether);
    }

    function test_retirar_sinSerDuenoRevierte() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pagador)
        );
        vm.prank(pagador);
        pasarela.retirar(payable(pagador), 1 ether);

        assertEq(address(pasarela).balance, 1 ether);
    }

    function test_retirar_aLaDireccionCeroRevierte() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(PasarelaCargas.DestinoInvalido.selector);
        vm.prank(dueno);
        pasarela.retirar(payable(address(0)), 1 ether);
    }

    function test_retirar_ceroRevierte() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(PasarelaCargas.MontoCero.selector);
        vm.prank(dueno);
        pasarela.retirar(payable(tesoreria), 0);
    }

    function test_retirar_masQueElSaldoRevierte() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(PasarelaCargas.SaldoInsuficiente.selector, 1 ether, 1 ether + 1)
        );
        vm.prank(dueno);
        pasarela.retirar(payable(tesoreria), 1 ether + 1);
    }

    function test_retirar_aUnDestinoQueRechazaEthRevierteEntero() public {
        _cargar(REFERENCIA, 1 ether);
        address destino = address(new DestinoQueRechazaEth());

        vm.expectRevert(PasarelaCargas.TransferenciaFallida.selector);
        vm.prank(dueno);
        pasarela.retirar(payable(destino), 1 ether);

        assertEq(address(pasarela).balance, 1 ether);
        assertEq(destino.balance, 0);
    }

    function test_retirar_todoElSaldoDejaElContratoEnCero() public {
        _cargar(REFERENCIA, 1 ether);

        vm.prank(dueno);
        pasarela.retirar(payable(tesoreria), 1 ether);

        assertEq(tesoreria.balance, 1 ether);
        assertEq(address(pasarela).balance, 0);
    }

    function test_retirar_noPermiteReentrarDesdeElDestino() public {
        DuenoQueReentraEnRetirar atacante = new DuenoQueReentraEnRetirar();
        pasarela = new PasarelaCargas(address(atacante));
        atacante.apuntarA(pasarela);
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(PasarelaCargas.TransferenciaFallida.selector);
        atacante.retirar(0.5 ether);

        assertEq(address(pasarela).balance, 1 ether);
        assertEq(address(atacante).balance, 0);
    }

    function test_traspaso_elNuevoDuenoSoloLoEsAlAceptar() public {
        address nuevoDueno = makeAddr("nuevoDueno");
        _cargar(REFERENCIA, 1 ether);

        vm.prank(dueno);
        pasarela.transferOwnership(nuevoDueno);
        assertEq(pasarela.owner(), dueno);
        assertEq(pasarela.pendingOwner(), nuevoDueno);

        vm.prank(nuevoDueno);
        pasarela.acceptOwnership();
        assertEq(pasarela.owner(), nuevoDueno);

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, dueno));
        vm.prank(dueno);
        pasarela.retirar(payable(tesoreria), 1 ether);

        vm.prank(nuevoDueno);
        pasarela.retirar(payable(tesoreria), 1 ether);
        assertEq(tesoreria.balance, 1 ether);
    }

    function test_traspaso_soloElPropuestoPuedeAceptar() public {
        address nuevoDueno = makeAddr("nuevoDueno");
        vm.prank(dueno);
        pasarela.transferOwnership(nuevoDueno);

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pagador)
        );
        vm.prank(pagador);
        pasarela.acceptOwnership();
        assertEq(pasarela.owner(), dueno);
    }

    function testFuzz_retirar_elDestinoRecibeExactamenteElMonto(uint256 cargado, uint256 monto)
        public
    {
        cargado = bound(cargado, 1, 1000 ether);
        monto = bound(monto, 1, cargado);
        vm.deal(pagador, cargado);
        _cargar(REFERENCIA, cargado);

        vm.prank(dueno);
        pasarela.retirar(payable(tesoreria), monto);

        assertEq(tesoreria.balance, monto);
        assertEq(address(pasarela).balance, cargado - monto);
    }
}
