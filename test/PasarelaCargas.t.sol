// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";
import {EscenarioPasarela} from "./utils/EscenarioPasarela.sol";
import {DestinoQueRechazaEth, DuenoQueReentraEnRetirar} from "./utils/Atacantes.sol";

contract PasarelaCargasTest is EscenarioPasarela {
    address internal pagador;
    address internal otroPagador;

    bytes32 internal constant REFERENCIA = keccak256("carga-1");

    function setUp() public override {
        super.setUp();
        pagador = _nuevoPagador("pagador");
        otroPagador = _nuevoPagador("otroPagador");
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
        _cargarDesde(pagador, referencia, monto);
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

    function test_cargar_conMontoCeroRevierte() public {
        vm.expectRevert(PasarelaCargas.MontoCero.selector);
        _cargar(REFERENCIA, 0);

        assertFalse(pasarela.pagada(REFERENCIA));
    }

    function test_cargar_conReferenciaVaciaRevierte() public {
        vm.expectRevert(PasarelaCargas.ReferenciaVacia.selector);
        _cargar(bytes32(0), 1 ether);
    }

    function test_cargar_unaReferenciaYaPagadaRevierteAunqueCambienPagadorYMonto() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(
            abi.encodeWithSelector(PasarelaCargas.ReferenciaYaPagada.selector, REFERENCIA)
        );
        vm.prank(otroPagador);
        pasarela.cargar{value: 2 ether}(REFERENCIA);

        assertEq(address(pasarela).balance, 1 ether);
        assertEq(otroPagador.balance, 10 ether);
    }

    function test_cargar_otroPagadorPuedePagarOtraReferencia() public {
        _cargar(REFERENCIA, 1 ether);
        bytes32 otraReferencia = keccak256("carga-2");

        vm.prank(otroPagador);
        pasarela.cargar{value: 2 ether}(otraReferencia);

        assertTrue(pasarela.pagada(otraReferencia));
        assertEq(address(pasarela).balance, 3 ether);
    }

    function test_ethSinDatosRevierte() public {
        vm.prank(pagador);
        (bool ok, bytes memory error_) = address(pasarela).call{value: 1 ether}("");

        assertFalse(ok);
        assertEq(error_, abi.encodeWithSelector(PasarelaCargas.PagoSinReferencia.selector));
        assertEq(address(pasarela).balance, 0);
    }

    function test_ethConDatosDesconocidosRevierte() public {
        vm.prank(pagador);
        (bool ok, bytes memory error_) =
            address(pasarela).call{value: 1 ether}(abi.encodeWithSignature("depositar()"));

        assertFalse(ok);
        assertEq(error_, abi.encodeWithSelector(PasarelaCargas.PagoSinReferencia.selector));
        assertEq(address(pasarela).balance, 0);
    }

    function testFuzz_cargar_registraCualquierMontoYReferenciaValidos(
        address quien,
        bytes32 referencia,
        uint256 monto
    ) public {
        vm.assume(referencia != bytes32(0));
        vm.assume(quien != address(0) && quien != address(pasarela));
        assumeNotPrecompile(quien);
        assumeNotForgeAddress(quien);
        monto = bound(monto, 1, 1000 ether);
        vm.deal(quien, monto);

        vm.expectEmit(true, true, false, true, address(pasarela));
        emit CargaRegistrada(referencia, quien, monto);

        vm.prank(quien);
        pasarela.cargar{value: monto}(referencia);

        assertTrue(pasarela.pagada(referencia));
        assertEq(address(pasarela).balance, monto);
    }

    function testFuzz_cargar_laMismaReferenciaNuncaSePagaDosVeces(
        bytes32 referencia,
        uint256 primerMonto,
        uint256 segundoMonto
    ) public {
        vm.assume(referencia != bytes32(0));
        primerMonto = bound(primerMonto, 1, 5 ether);
        segundoMonto = bound(segundoMonto, 1, 5 ether);
        _cargar(referencia, primerMonto);

        vm.expectRevert(
            abi.encodeWithSelector(PasarelaCargas.ReferenciaYaPagada.selector, referencia)
        );
        vm.prank(otroPagador);
        pasarela.cargar{value: segundoMonto}(referencia);

        assertEq(address(pasarela).balance, primerMonto);
    }

    function test_pausar_frenaLasCargas() public {
        vm.expectEmit(false, false, false, true, address(pasarela));
        emit Pausable.Paused(dueno);
        vm.prank(dueno);
        pasarela.pausar();

        assertTrue(pasarela.paused());
        vm.expectRevert(Pausable.EnforcedPause.selector);
        _cargar(REFERENCIA, 1 ether);
        assertFalse(pasarela.pagada(REFERENCIA));
        assertEq(pagador.balance, 10 ether);
    }

    function test_reanudar_vuelveAAceptarCargas() public {
        vm.startPrank(dueno);
        pasarela.pausar();
        vm.expectEmit(false, false, false, true, address(pasarela));
        emit Pausable.Unpaused(dueno);
        pasarela.reanudar();
        vm.stopPrank();

        assertFalse(pasarela.paused());
        _cargar(REFERENCIA, 1 ether);
        assertTrue(pasarela.pagada(REFERENCIA));
    }

    function test_pausarYReanudar_sinSerDuenoRevierten() public {
        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pagador)
        );
        vm.prank(pagador);
        pasarela.pausar();

        vm.prank(dueno);
        pasarela.pausar();

        vm.expectRevert(
            abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, pagador)
        );
        vm.prank(pagador);
        pasarela.reanudar();
        assertTrue(pasarela.paused());
    }

    function test_pausar_dosVecesRevierteYReanudarSinPausaTambien() public {
        vm.expectRevert(Pausable.ExpectedPause.selector);
        vm.prank(dueno);
        pasarela.reanudar();

        vm.startPrank(dueno);
        pasarela.pausar();
        vm.expectRevert(Pausable.EnforcedPause.selector);
        pasarela.pausar();
        vm.stopPrank();
    }

    function test_retirar_sigueFuncionandoConElContratoPausado() public {
        _cargar(REFERENCIA, 1 ether);

        vm.startPrank(dueno);
        pasarela.pausar();
        pasarela.retirar(payable(tesoreria), 1 ether);
        vm.stopPrank();

        assertEq(tesoreria.balance, 1 ether);
        assertEq(address(pasarela).balance, 0);
    }

    function test_renunciar_alContratoRevierteParaNoDejarLosFondosSinDueno() public {
        _cargar(REFERENCIA, 1 ether);

        vm.expectRevert(PasarelaCargas.RenunciaNoPermitida.selector);
        vm.prank(dueno);
        pasarela.renounceOwnership();

        assertEq(pasarela.owner(), dueno);
    }
}
