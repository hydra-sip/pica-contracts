// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Test} from "forge-std/Test.sol";
import {PasarelaRetiros} from "../../src/PasarelaRetiros.sol";

/// @dev Escenario común de los tests de retiros: una pasarela fondeada, con su dueño y la clave
/// del firmante (el back), y helpers para firmar permisos y cobrarlos.
abstract contract EscenarioRetiros is Test {
    event RetiroCobrado(bytes32 indexed referencia, address indexed destino, uint256 monto);
    event FirmanteCambiado(address indexed anterior, address indexed nuevo);
    event Fondeado(address indexed origen, uint256 monto);
    event FondosRetirados(address indexed destino, uint256 monto);

    uint256 internal constant FONDOS_INICIALES = 10 ether;

    PasarelaRetiros internal retiros;
    address internal dueno = makeAddr("dueno");
    address internal tesoreria = makeAddr("tesoreria");
    address internal firmante;
    uint256 internal claveFirmante;

    function setUp() public virtual {
        (firmante, claveFirmante) = makeAddrAndKey("firmante");
        retiros = new PasarelaRetiros(dueno, firmante);
        _fondear(FONDOS_INICIALES);
    }

    function _fondear(uint256 monto) internal {
        vm.deal(tesoreria, tesoreria.balance + monto);
        vm.prank(tesoreria);
        (bool ok,) = address(retiros).call{value: monto}("");
        assertTrue(ok);
    }

    /// @dev El permiso que firmaría el back con `clave`, en el formato que espera `cobrar`.
    function _firmarCon(
        uint256 clave,
        bytes32 referencia,
        address destino,
        uint256 monto,
        uint256 vence
    ) internal view returns (bytes memory) {
        (uint8 v, bytes32 r, bytes32 s) =
            vm.sign(clave, retiros.digestDelRetiro(referencia, destino, monto, vence));
        return abi.encodePacked(r, s, v);
    }

    function _firmar(bytes32 referencia, address destino, uint256 monto, uint256 vence)
        internal
        view
        returns (bytes memory)
    {
        return _firmarCon(claveFirmante, referencia, destino, monto, vence);
    }

    /// @dev Firma el permiso para `destino`, con una hora de vencimiento, y lo cobra desde ahí.
    function _cobrar(address destino, bytes32 referencia, uint256 monto) internal {
        uint256 vence = block.timestamp + 1 hours;
        bytes memory firma = _firmar(referencia, destino, monto, vence);
        vm.prank(destino);
        retiros.cobrar(referencia, monto, vence, firma);
    }
}
