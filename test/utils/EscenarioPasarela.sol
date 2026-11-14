// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {PasarelaCargas} from "../../src/PasarelaCargas.sol";

/// @dev Escenario común de los tests: una pasarela recién desplegada con su dueño, una tesorería
/// a la que retirar y helpers para sumar pagadores con fondos y pagar cargas.
abstract contract EscenarioPasarela is Test {
    event CargaRegistrada(bytes32 indexed referencia, address indexed pagador, uint256 monto);
    event FondosRetirados(address indexed destino, uint256 monto);

    uint256 internal constant FONDOS_INICIALES = 10 ether;

    PasarelaCargas internal pasarela;
    address internal dueno = makeAddr("dueno");
    address internal tesoreria = makeAddr("tesoreria");

    function setUp() public virtual {
        pasarela = new PasarelaCargas(dueno);
    }

    /// @dev Un pagador nuevo con `FONDOS_INICIALES` de ETH.
    function _nuevoPagador(string memory nombre) internal returns (address pagador) {
        pagador = makeAddr(nombre);
        vm.deal(pagador, FONDOS_INICIALES);
    }

    function _cargarDesde(address pagador, bytes32 referencia, uint256 monto) internal {
        vm.prank(pagador);
        pasarela.cargar{value: monto}(referencia);
    }
}
