// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {PasarelaRetiros} from "../src/PasarelaRetiros.sol";
import {EscenarioRetiros} from "./utils/EscenarioRetiros.sol";

/// @dev Opera la pasarela como lo harían el back (firma permisos), los usuarios (cobran, a veces
/// dos veces o tarde) y el dueño (fondea, retira y pausa), y lleva la cuenta de lo que pasó para
/// que el test de invariantes la compare con lo que dice el contrato.
contract OperadorDeRetiros is Test {
    uint256 public constant CANTIDAD_DE_REFERENCIAS = 20;

    PasarelaRetiros internal immutable retiros;
    address internal immutable dueno;
    uint256 internal immutable claveFirmante;
    address[] internal usuarios;

    uint256 public totalFondeado;
    uint256 public totalCobrado;
    uint256 public totalRetirado;
    mapping(bytes32 referencia => uint256) public vecesCobrado;
    mapping(address usuario => uint256) public cobradoPor;

    constructor(PasarelaRetiros retiros_, address dueno_, uint256 claveFirmante_) {
        retiros = retiros_;
        dueno = dueno_;
        claveFirmante = claveFirmante_;
        usuarios.push(makeAddr("usuario-1"));
        usuarios.push(makeAddr("usuario-2"));
        usuarios.push(makeAddr("usuario-3"));
    }

    function referencia(uint256 indice) public pure returns (bytes32) {
        return keccak256(abi.encode("retiro", indice % CANTIDAD_DE_REFERENCIAS));
    }

    function cantidadDeUsuarios() external view returns (uint256) {
        return usuarios.length;
    }

    function usuario(uint256 indice) external view returns (address) {
        return usuarios[indice];
    }

    /// @dev Un usuario cobra un permiso válido. Si la referencia ya se cobró, tiene que revertir.
    function cobrar(uint256 semillaUsuario, uint256 indiceReferencia, uint256 monto) external {
        if (retiros.paused() || address(retiros).balance == 0) return;
        bytes32 ref = referencia(indiceReferencia);
        address destino = usuarios[semillaUsuario % usuarios.length];
        monto = bound(monto, 1, address(retiros).balance);
        uint256 vence = block.timestamp + 1 hours;
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(claveFirmante, retiros.digestDelRetiro(ref, destino, monto, vence));

        vm.prank(destino);
        try retiros.cobrar(ref, monto, vence, abi.encodePacked(r, s, v)) {
            totalCobrado += monto;
            vecesCobrado[ref] += 1;
            cobradoPor[destino] += monto;
        } catch (bytes memory motivo) {
            assertEq(motivo, abi.encodeWithSelector(PasarelaRetiros.RetiroYaCobrado.selector, ref));
        }
    }

    /// @dev Un usuario intenta cobrar un permiso vencido: nunca paga.
    function cobrarTarde(uint256 semillaUsuario, uint256 indiceReferencia) external {
        bytes32 ref = referencia(indiceReferencia);
        address destino = usuarios[semillaUsuario % usuarios.length];
        uint256 vence = block.timestamp;
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(claveFirmante, retiros.digestDelRetiro(ref, destino, 1, vence));
        vm.warp(block.timestamp + 1);

        vm.prank(destino);
        try retiros.cobrar(ref, 1, vence, abi.encodePacked(r, s, v)) {
            revert("pago un permiso vencido");
        } catch {}
    }

    function fondear(uint256 monto) external {
        monto = bound(monto, 1, 100 ether);
        vm.deal(address(this), monto);
        (bool ok,) = address(retiros).call{value: monto}("");
        assertTrue(ok);
        totalFondeado += monto;
    }

    function retirar(uint256 monto) external {
        uint256 saldo = address(retiros).balance;
        if (saldo == 0) return;
        monto = bound(monto, 1, saldo);
        vm.prank(dueno);
        retiros.retirar(payable(dueno), monto);
        totalRetirado += monto;
    }

    function alternarPausa() external {
        vm.startPrank(dueno);
        if (retiros.paused()) retiros.reanudar();
        else retiros.pausar();
        vm.stopPrank();
    }
}

contract PasarelaRetirosInvariantesTest is EscenarioRetiros {
    OperadorDeRetiros internal operador;

    function setUp() public override {
        super.setUp();
        operador = new OperadorDeRetiros(retiros, dueno, claveFirmante);
        targetContract(address(operador));
    }

    /// @dev Al menos y no igual: `selfdestruct` puede meter ETH sin pasar por `receive`.
    function invariant_elSaldoCubreLoFondeadoMenosLoPagado() public view {
        assertGe(
            address(retiros).balance,
            FONDOS_INICIALES + operador.totalFondeado() - operador.totalCobrado()
                - operador.totalRetirado()
        );
    }

    function invariant_ningunRetiroSeCobraDosVeces() public view {
        for (uint256 i = 0; i < operador.CANTIDAD_DE_REFERENCIAS(); i++) {
            bytes32 ref = operador.referencia(i);
            uint256 veces = operador.vecesCobrado(ref);
            assertLe(veces, 1);
            assertEq(retiros.cobrado(ref), veces == 1);
        }
    }

    function invariant_cadaUsuarioRecibioExactamenteLoQueCobro() public view {
        for (uint256 i = 0; i < operador.cantidadDeUsuarios(); i++) {
            address usuario = operador.usuario(i);
            assertEq(usuario.balance, operador.cobradoPor(usuario));
        }
    }
}
