// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {PasarelaCargas} from "../../src/PasarelaCargas.sol";

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
