// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Pasarela de cargas de PICA
/// @notice Recibe en ETH el pago de una carga de saldo identificada por la referencia que genera
/// el back, y emite un evento que el back lee para acreditar la carga en la billetera.
/// @dev El contrato registra el monto en wei; la cotización a pesos y la verificación del monto
/// esperado son responsabilidad del back.
contract PasarelaCargas is Ownable2Step, Pausable, ReentrancyGuard {
    /// @notice Indica si una referencia ya fue pagada.
    mapping(bytes32 referencia => bool) public pagada;

    /// @notice Se emite cuando se paga una carga.
    event CargaRegistrada(bytes32 indexed referencia, address indexed pagador, uint256 monto);

    constructor(address dueno) Ownable(dueno) {}

    /// @notice Paga la carga identificada por `referencia` con el ETH enviado.
    function cargar(bytes32 referencia) external payable nonReentrant {
        pagada[referencia] = true;
        emit CargaRegistrada(referencia, msg.sender, msg.value);
    }
}
