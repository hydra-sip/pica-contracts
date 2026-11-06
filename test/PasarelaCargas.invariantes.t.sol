// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {PasarelaCargas} from "../src/PasarelaCargas.sol";

/// @dev Opera la pasarela como lo harían los pagadores y el dueño, y lleva la cuenta de lo que
/// pasó para que el test de invariantes la compare con lo que dice el contrato.
contract OperadorDeLaPasarela is Test {
    uint256 public constant CANTIDAD_DE_REFERENCIAS = 20;

    PasarelaCargas internal immutable pasarela;
    address internal immutable dueno;
    address[] internal pagadores;
    address[] internal destinos;

    uint256 public totalCargado;
    uint256 public totalRetirado;
    mapping(bytes32 referencia => bool) public pagoRegistrado;

    constructor(PasarelaCargas pasarela_, address dueno_) {
        pasarela = pasarela_;
        dueno = dueno_;
        pagadores.push(makeAddr("pagador-1"));
        pagadores.push(makeAddr("pagador-2"));
        pagadores.push(makeAddr("pagador-3"));
        destinos.push(makeAddr("tesoreria"));
        destinos.push(pagadores[0]);
    }

    function referencia(uint256 indice) public pure returns (bytes32) {
        return keccak256(abi.encode("referencia", indice % CANTIDAD_DE_REFERENCIAS));
    }

    function cargar(uint256 semillaPagador, uint256 indiceReferencia, uint256 monto) external {
        bytes32 ref = referencia(indiceReferencia);
        if (pasarela.paused() || pasarela.pagada(ref)) return;

        address pagador = pagadores[semillaPagador % pagadores.length];
        monto = bound(monto, 1, 100 ether);
        vm.deal(pagador, pagador.balance + monto);

        vm.prank(pagador);
        pasarela.cargar{value: monto}(ref);

        totalCargado += monto;
        pagoRegistrado[ref] = true;
    }

    function retirar(uint256 semillaDestino, uint256 monto) external {
        uint256 saldo = address(pasarela).balance;
        if (saldo == 0) return;

        monto = bound(monto, 1, saldo);
        vm.prank(dueno);
        pasarela.retirar(payable(destinos[semillaDestino % destinos.length]), monto);

        totalRetirado += monto;
    }

    function alternarPausa() external {
        vm.startPrank(dueno);
        if (pasarela.paused()) pasarela.reanudar();
        else pasarela.pausar();
        vm.stopPrank();
    }
}

contract PasarelaCargasInvariantesTest is Test {
    PasarelaCargas internal pasarela;
    OperadorDeLaPasarela internal operador;

    function setUp() public {
        address dueno = makeAddr("dueno");
        pasarela = new PasarelaCargas(dueno);
        operador = new OperadorDeLaPasarela(pasarela, dueno);
        targetContract(address(operador));
    }

    /// @dev Al menos y no igual: `selfdestruct` puede meter ETH sin pasar por `cargar`.
    function invariant_elSaldoCubreLoCargadoMenosLoRetirado() public view {
        assertGe(address(pasarela).balance, operador.totalCargado() - operador.totalRetirado());
    }

    function invariant_soloFiguranPagadasLasReferenciasQueSePagaron() public view {
        for (uint256 i = 0; i < operador.CANTIDAD_DE_REFERENCIAS(); i++) {
            bytes32 ref = operador.referencia(i);
            assertEq(pasarela.pagada(ref), operador.pagoRegistrado(ref));
        }
    }
}
