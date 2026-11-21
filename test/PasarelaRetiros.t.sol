// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {PasarelaRetiros} from "../src/PasarelaRetiros.sol";
import {EscenarioRetiros} from "./utils/EscenarioRetiros.sol";
import {DestinoQueRechazaEth, DestinoQueReentraEnCobrar} from "./utils/Atacantes.sol";

contract PasarelaRetirosTest is EscenarioRetiros {
    address internal ana = makeAddr("ana");
    address internal bruno = makeAddr("bruno");

    bytes32 internal constant REFERENCIA = keccak256("retiro-1");

    // --- constructor ---

    function test_constructor_dejaAlDuenoYAlFirmante() public view {
        assertEq(retiros.owner(), dueno);
        assertEq(retiros.firmante(), firmante);
        assertFalse(retiros.paused());
    }

    function test_constructor_emiteElFirmanteInicial() public {
        vm.expectEmit(true, true, false, false);
        emit FirmanteCambiado(address(0), firmante);
        new PasarelaRetiros(dueno, firmante);
    }

    function test_constructor_sinFirmanteRevierte() public {
        vm.expectRevert(PasarelaRetiros.DireccionInvalida.selector);
        new PasarelaRetiros(dueno, address(0));
    }

    // --- cobrar ---

    function test_cobrar_pagaALaWalletYEmiteElEvento() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 0.3 ether, vence);

        vm.expectEmit(true, true, false, true, address(retiros));
        emit RetiroCobrado(REFERENCIA, ana, 0.3 ether);

        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 0.3 ether, vence, firma);

        assertTrue(retiros.cobrado(REFERENCIA));
        assertEq(ana.balance, 0.3 ether);
        assertEq(address(retiros).balance, 9.7 ether);
    }

    function test_cobrar_justoAlVencerTodaviaVale() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 1 ether, vence);
        vm.warp(vence);

        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);

        assertEq(ana.balance, 1 ether);
    }

    function test_cobrar_conElPermisoVencidoRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 1 ether, vence);
        vm.warp(vence + 1);

        vm.expectRevert(abi.encodeWithSelector(PasarelaRetiros.PermisoVencido.selector, vence));
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);

        assertFalse(retiros.cobrado(REFERENCIA));
        assertEq(ana.balance, 0);
    }

    function test_cobrar_dosVecesElMismoRetiroRevierte() public {
        _cobrar(ana, REFERENCIA, 1 ether);
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 1 ether, vence);

        vm.expectRevert(
            abi.encodeWithSelector(PasarelaRetiros.RetiroYaCobrado.selector, REFERENCIA)
        );
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);

        assertEq(ana.balance, 1 ether);
        assertEq(address(retiros).balance, 9 ether);
    }

    function test_cobrar_desdeOtraWalletRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firmaParaAna = _firmar(REFERENCIA, ana, 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(bruno);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firmaParaAna);

        assertEq(bruno.balance, 0);
        assertFalse(retiros.cobrado(REFERENCIA));
    }

    function test_cobrar_otroMontoQueElFirmadoRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 2 ether, vence, firma);
    }

    function test_cobrar_conOtroVencimientoQueElFirmadoRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence + 1 days, firma);
    }

    function test_cobrar_conLaFirmaDeOtraClaveRevierte() public {
        (, uint256 claveAjena) = makeAddrAndKey("ajeno");
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmarCon(claveAjena, REFERENCIA, ana, 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);
    }

    function test_cobrar_conUnaFirmaMalFormadaRevierte() public {
        uint256 vence = block.timestamp + 1 hours;

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, hex"1234");
    }

    function test_cobrar_sinReferenciaRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(bytes32(0), ana, 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.ReferenciaVacia.selector);
        vm.prank(ana);
        retiros.cobrar(bytes32(0), 1 ether, vence, firma);
    }

    function test_cobrar_ceroRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 0, vence);

        vm.expectRevert(PasarelaRetiros.MontoCero.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 0, vence, firma);
    }

    function test_cobrar_masQueLosFondosRevierteYElPermisoSigueValiendo() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 11 ether, vence);

        vm.expectRevert(
            abi.encodeWithSelector(PasarelaRetiros.SaldoInsuficiente.selector, 10 ether, 11 ether)
        );
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 11 ether, vence, firma);

        _fondear(1 ether);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 11 ether, vence, firma);
        assertEq(ana.balance, 11 ether);
        assertEq(address(retiros).balance, 0);
    }

    function test_cobrar_conLaPasarelaPausadaRevierte() public {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, 1 ether, vence);
        vm.prank(dueno);
        retiros.pausar();

        vm.expectRevert(Pausable.EnforcedPause.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);

        vm.prank(dueno);
        retiros.reanudar();
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);
        assertEq(ana.balance, 1 ether);
    }

    function test_cobrar_aUnaWalletQueRechazaElEthRevierte() public {
        DestinoQueRechazaEth destino = new DestinoQueRechazaEth();
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, address(destino), 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.TransferenciaFallida.selector);
        vm.prank(address(destino));
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);

        assertFalse(retiros.cobrado(REFERENCIA));
        assertEq(address(retiros).balance, 10 ether);
    }

    function test_cobrar_noPuedeReentrarParaCobrarOtroRetiro() public {
        DestinoQueReentraEnCobrar atacante = new DestinoQueReentraEnCobrar(retiros);
        uint256 vence = block.timestamp + 1 hours;
        bytes32 otraReferencia = keccak256("retiro-2");
        atacante.prepararSegundoCobro(
            otraReferencia,
            1 ether,
            vence,
            _firmar(otraReferencia, address(atacante), 1 ether, vence)
        );
        bytes memory firma = _firmar(REFERENCIA, address(atacante), 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.TransferenciaFallida.selector);
        atacante.cobrar(REFERENCIA, 1 ether, vence, firma);

        assertFalse(retiros.cobrado(REFERENCIA));
        assertFalse(retiros.cobrado(otraReferencia));
        assertEq(address(atacante).balance, 0);
        assertEq(address(retiros).balance, 10 ether);
    }

    // --- firmante ---

    function test_cambiarFirmante_invalidaLosPermisosDelAnterior() public {
        (address nuevo, uint256 claveNueva) = makeAddrAndKey("nuevo-firmante");
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firmaVieja = _firmar(REFERENCIA, ana, 1 ether, vence);

        vm.expectEmit(true, true, false, false, address(retiros));
        emit FirmanteCambiado(firmante, nuevo);
        vm.prank(dueno);
        retiros.cambiarFirmante(nuevo);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firmaVieja);

        bytes memory firmaNueva = _firmarCon(claveNueva, REFERENCIA, ana, 1 ether, vence);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firmaNueva);
        assertEq(retiros.firmante(), nuevo);
        assertEq(ana.balance, 1 ether);
    }

    function test_cambiarFirmante_sinSerDuenoRevierte() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ana));
        vm.prank(ana);
        retiros.cambiarFirmante(ana);

        assertEq(retiros.firmante(), firmante);
    }

    function test_cambiarFirmante_aLaDireccionCeroRevierte() public {
        vm.expectRevert(PasarelaRetiros.DireccionInvalida.selector);
        vm.prank(dueno);
        retiros.cambiarFirmante(address(0));
    }

    // --- retirar ---

    function test_retirar_transfiereLoQueSobraYEmiteElEvento() public {
        vm.expectEmit(true, false, false, true, address(retiros));
        emit FondosRetirados(dueno, 4 ether);

        vm.prank(dueno);
        retiros.retirar(payable(dueno), 4 ether);

        assertEq(dueno.balance, 4 ether);
        assertEq(address(retiros).balance, 6 ether);
    }

    function test_retirar_sinSerDuenoRevierte() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ana));
        vm.prank(ana);
        retiros.retirar(payable(ana), 1 ether);
    }

    function test_retirar_aLaDireccionCeroRevierte() public {
        vm.expectRevert(PasarelaRetiros.DireccionInvalida.selector);
        vm.prank(dueno);
        retiros.retirar(payable(address(0)), 1 ether);
    }

    function test_retirar_ceroRevierte() public {
        vm.expectRevert(PasarelaRetiros.MontoCero.selector);
        vm.prank(dueno);
        retiros.retirar(payable(dueno), 0);
    }

    function test_retirar_masQueLosFondosRevierte() public {
        vm.expectRevert(
            abi.encodeWithSelector(PasarelaRetiros.SaldoInsuficiente.selector, 10 ether, 11 ether)
        );
        vm.prank(dueno);
        retiros.retirar(payable(dueno), 11 ether);
    }

    function test_retirar_aUnDestinoQueRechazaElEthRevierte() public {
        DestinoQueRechazaEth destino = new DestinoQueRechazaEth();

        vm.expectRevert(PasarelaRetiros.TransferenciaFallida.selector);
        vm.prank(dueno);
        retiros.retirar(payable(address(destino)), 1 ether);
    }

    function test_retirar_funcionaConLaPasarelaPausada() public {
        vm.startPrank(dueno);
        retiros.pausar();
        retiros.retirar(payable(dueno), 1 ether);
        vm.stopPrank();

        assertEq(dueno.balance, 1 ether);
    }

    // --- pausa y dueño ---

    function test_pausar_sinSerDuenoRevierte() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ana));
        vm.prank(ana);
        retiros.pausar();
    }

    function test_reanudar_sinSerDuenoRevierte() public {
        vm.prank(dueno);
        retiros.pausar();

        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ana));
        vm.prank(ana);
        retiros.reanudar();
    }

    function test_renunciar_siempreRevierte() public {
        vm.expectRevert(PasarelaRetiros.RenunciaNoPermitida.selector);
        vm.prank(dueno);
        retiros.renounceOwnership();

        assertEq(retiros.owner(), dueno);
    }

    function test_renunciar_sinSerDuenoRevierte() public {
        vm.expectRevert(abi.encodeWithSelector(Ownable.OwnableUnauthorizedAccount.selector, ana));
        vm.prank(ana);
        retiros.renounceOwnership();
    }

    function test_traspasoDeDueno_esEnDosPasos() public {
        vm.prank(dueno);
        retiros.transferOwnership(ana);
        assertEq(retiros.owner(), dueno);

        vm.prank(ana);
        retiros.acceptOwnership();
        assertEq(retiros.owner(), ana);
    }

    // --- fondeo ---

    function test_recibirEth_fondeaLaPasarelaYEmiteElEvento() public {
        vm.deal(ana, 2 ether);
        vm.expectEmit(true, false, false, true, address(retiros));
        emit Fondeado(ana, 2 ether);

        vm.prank(ana);
        (bool ok,) = address(retiros).call{value: 2 ether}("");

        assertTrue(ok);
        assertEq(address(retiros).balance, 12 ether);
    }

    function test_recibirEth_sinMontoRevierte() public {
        vm.prank(ana);
        (bool ok, bytes memory motivo) = address(retiros).call("");

        assertFalse(ok);
        assertEq(motivo, abi.encodeWithSelector(PasarelaRetiros.MontoCero.selector));
    }

    function test_llamadaDesconocida_revierte() public {
        vm.deal(ana, 1 ether);
        vm.prank(ana);
        (bool ok, bytes memory motivo) =
            address(retiros).call{value: 1 ether}(abi.encodeWithSignature("retirarTodo()"));

        assertFalse(ok);
        assertEq(motivo, abi.encodeWithSelector(PasarelaRetiros.LlamadaDesconocida.selector));
        assertEq(address(retiros).balance, 10 ether);
    }

    // --- formato del permiso ---

    /// @dev El back arma el hash a mano, así que el formato EIP-712 tiene que ser exactamente este.
    function test_digestDelRetiro_sigueElFormatoEip712() public view {
        bytes32 dominio = keccak256(
            abi.encode(
                keccak256(
                    "EIP712Domain(string name,string version,uint256 chainId,address verifyingContract)"
                ),
                keccak256("PasarelaRetiros"),
                keccak256("1"),
                block.chainid,
                address(retiros)
            )
        );
        bytes32 estructura = keccak256(
            abi.encode(
                keccak256("Retiro(bytes32 referencia,address destino,uint256 monto,uint256 vence)"),
                REFERENCIA,
                ana,
                1 ether,
                uint256(1_800_000_000)
            )
        );

        assertEq(
            retiros.digestDelRetiro(REFERENCIA, ana, 1 ether, 1_800_000_000),
            keccak256(abi.encodePacked("\x19\x01", dominio, estructura))
        );
    }

    // --- fuzz ---

    function testFuzz_cobrar_pagaExactamenteLoFirmado(
        bytes32 referencia,
        uint256 monto,
        uint256 plazo
    ) public {
        vm.assume(referencia != bytes32(0));
        monto = bound(monto, 1, FONDOS_INICIALES);
        uint256 vence = block.timestamp + bound(plazo, 0, 365 days);
        bytes memory firma = _firmar(referencia, ana, monto, vence);

        vm.prank(ana);
        retiros.cobrar(referencia, monto, vence, firma);

        assertTrue(retiros.cobrado(referencia));
        assertEq(ana.balance, monto);
        assertEq(address(retiros).balance, FONDOS_INICIALES - monto);
    }

    function testFuzz_cobrar_otroMontoQueElFirmadoNuncaPaga(uint256 firmado, uint256 pedido)
        public
    {
        firmado = bound(firmado, 1, FONDOS_INICIALES);
        pedido = bound(pedido, 1, FONDOS_INICIALES);
        vm.assume(firmado != pedido);
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(REFERENCIA, ana, firmado, vence);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, pedido, vence, firma);
    }

    function testFuzz_cobrar_unaClaveQueNoEsLaDelFirmanteNuncaPaga(uint256 clave) public {
        clave = bound(clave, 1, SECP256K1_ORDER - 1);
        vm.assume(clave != claveFirmante);
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmarCon(clave, REFERENCIA, ana, 1 ether, vence);

        vm.expectRevert(PasarelaRetiros.FirmaInvalida.selector);
        vm.prank(ana);
        retiros.cobrar(REFERENCIA, 1 ether, vence, firma);
    }
}

/// @dev Un permiso fijo que el back reproduce en sus tests (`FirmanteDeRetirosTest`): si cambia el
/// formato de un lado, el test del otro lado deja de coincidir. La clave es la segunda cuenta de
/// prueba de anvil, pública: nunca se usa en una red real.
contract PermisoDeReferenciaTest is EscenarioRetiros {
    uint256 internal constant CLAVE_DE_PRUEBA =
        0x59c6995e998f97a5a0044966f0945389dc9e86dae88c7a8412f4603b6b78690d;
    address internal constant CONTRATO = address(0xCA5A5);
    address internal constant DESTINO = address(0xA1);
    uint256 internal constant MONTO = 0.0001 ether;
    uint256 internal constant VENCE = 1_800_000_000;

    function setUp() public override {
        vm.chainId(84532);
        deployCodeTo(
            "PasarelaRetiros.sol:PasarelaRetiros",
            abi.encode(dueno, vm.addr(CLAVE_DE_PRUEBA)),
            CONTRATO
        );
        retiros = PasarelaRetiros(payable(CONTRATO));
        _fondear(1 ether);
    }

    function test_elPermisoDeReferenciaCoincideConElDelBack() public {
        bytes32 referencia = keccak256("retiro-vector");
        bytes memory firma =
            hex"5a2ddedbb42999d93f58bf2668909a9cd6097533c0ced9306a2d61a260b3e35e416a2b2dc00aeadb9be0d04a2f3ffc0e62b31b544f1587e70fac623da997ef171c";

        assertEq(vm.addr(CLAVE_DE_PRUEBA), 0x70997970C51812dc3A010C7d01b50e0d17dc79C8);
        assertEq(
            retiros.digestDelRetiro(referencia, DESTINO, MONTO, VENCE),
            0x6b10001fa2c79ffc26d43ce1493718ea4c62e3563038a79a9d531c71b787bed9
        );
        assertEq(firma, _firmarCon(CLAVE_DE_PRUEBA, referencia, DESTINO, MONTO, VENCE));

        vm.warp(VENCE);
        vm.prank(DESTINO);
        retiros.cobrar(referencia, MONTO, VENCE, firma);
        assertEq(DESTINO.balance, MONTO);
    }
}
