// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {PasarelaCargas} from "../../src/PasarelaCargas.sol";
import {PasarelaRetiros} from "../../src/PasarelaRetiros.sol";

/// @dev Destino sin `receive` ni `fallback`: rechaza cualquier ETH.
contract DestinoQueRechazaEth {}

/// @dev Dueño y destino a la vez: al recibir el retiro intenta retirar de nuevo.
contract DuenoQueReentraEnRetirar {
    PasarelaCargas public pasarela;

    function apuntarA(PasarelaCargas pasarela_) external {
        pasarela = pasarela_;
    }

    function retirar(uint256 monto) external {
        pasarela.retirar(payable(address(this)), monto);
    }

    receive() external payable {
        if (address(pasarela).balance >= msg.value) {
            pasarela.retirar(payable(address(this)), msg.value);
        }
    }
}

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

/// @dev Wallet de un usuario que, al recibir su retiro, intenta cobrar otro permiso válido.
contract DestinoQueReentraEnCobrar {
    PasarelaRetiros internal immutable retiros;
    bytes32 internal referencia;
    uint256 internal monto;
    uint256 internal vence;
    bytes internal firma;

    constructor(PasarelaRetiros retiros_) {
        retiros = retiros_;
    }

    function prepararSegundoCobro(
        bytes32 referencia_,
        uint256 monto_,
        uint256 vence_,
        bytes calldata firma_
    ) external {
        referencia = referencia_;
        monto = monto_;
        vence = vence_;
        firma = firma_;
    }

    function cobrar(bytes32 ref, uint256 monto_, uint256 vence_, bytes calldata firma_) external {
        retiros.cobrar(ref, monto_, vence_, firma_);
    }

    receive() external payable {
        retiros.cobrar(referencia, monto, vence, firma);
    }
}
