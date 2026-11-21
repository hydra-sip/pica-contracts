// SPDX-License-Identifier: MIT
pragma solidity 0.8.38;

import {Ownable} from "@openzeppelin/contracts/access/Ownable.sol";
import {Ownable2Step} from "@openzeppelin/contracts/access/Ownable2Step.sol";
import {EIP712} from "@openzeppelin/contracts/utils/cryptography/EIP712.sol";
import {SignatureChecker} from "@openzeppelin/contracts/utils/cryptography/SignatureChecker.sol";
import {Pausable} from "@openzeppelin/contracts/utils/Pausable.sol";
import {ReentrancyGuard} from "@openzeppelin/contracts/utils/ReentrancyGuard.sol";

/// @title Pasarela de retiros de PICA
/// @notice Paga en ETH el retiro de saldo que un usuario pidió en la plataforma. El back descuenta
/// el saldo y firma un permiso (EIP-712) con la referencia, la wallet, el monto y el vencimiento;
/// el usuario lo cobra desde esa wallet con su propia transacción («pull over push»).
/// @dev El contrato registra el monto en wei; la cotización a pesos, los topes y el saldo del
/// usuario son responsabilidad del back. Se fondea con ETH (por ejemplo, con lo recaudado por
/// `PasarelaCargas`) y solo paga permisos firmados por `firmante`.
contract PasarelaRetiros is Ownable2Step, Pausable, ReentrancyGuard, EIP712 {
    /// @notice El tipo EIP-712 del permiso que firma el back.
    bytes32 public constant TIPO_RETIRO =
        keccak256("Retiro(bytes32 referencia,address destino,uint256 monto,uint256 vence)");

    /// @notice La cuenta del back que firma los permisos de retiro.
    address public firmante;

    /// @notice Indica si el retiro con esa referencia ya se cobró.
    mapping(bytes32 referencia => bool) public cobrado;

    /// @notice Se emite cuando un usuario cobra su retiro.
    event RetiroCobrado(bytes32 indexed referencia, address indexed destino, uint256 monto);

    /// @notice Se emite cuando el dueño cambia la cuenta que firma los permisos.
    event FirmanteCambiado(address indexed anterior, address indexed nuevo);

    /// @notice Se emite cuando entra ETH para pagar retiros.
    event Fondeado(address indexed origen, uint256 monto);

    /// @notice Se emite cuando el dueño retira fondos que sobran.
    event FondosRetirados(address indexed destino, uint256 monto);

    /// @notice El monto del retiro o del fondeo es 0.
    error MontoCero();

    /// @notice El retiro no tiene referencia.
    error ReferenciaVacia();

    /// @notice El destino o el firmante es la dirección cero.
    error DireccionInvalida();

    /// @notice El retiro con esa referencia ya se cobró.
    error RetiroYaCobrado(bytes32 referencia);

    /// @notice El permiso venció antes de cobrarse.
    error PermisoVencido(uint256 vence);

    /// @notice La firma no es del firmante, o es de otro retiro, otra wallet u otro monto.
    error FirmaInvalida();

    /// @notice El contrato no tiene fondos para pagar ese monto.
    error SaldoInsuficiente(uint256 saldo, uint256 monto);

    /// @notice El destino rechazó la transferencia.
    error TransferenciaFallida();

    /// @notice El dueño no puede renunciar: el contrato quedaría sin nadie que cambie el firmante.
    error RenunciaNoPermitida();

    /// @notice Llamada a una función que no existe.
    error LlamadaDesconocida();

    constructor(address dueno, address firmante_) Ownable(dueno) EIP712("PasarelaRetiros", "1") {
        if (firmante_ == address(0)) revert DireccionInvalida();
        firmante = firmante_;
        emit FirmanteCambiado(address(0), firmante_);
    }

    /// @notice Cobra el retiro `referencia` en la wallet que llama, con el permiso que firmó el
    /// back para esa wallet, ese monto y ese vencimiento.
    function cobrar(bytes32 referencia, uint256 monto, uint256 vence, bytes calldata firma)
        external
        nonReentrant
        whenNotPaused
    {
        // Checks
        if (referencia == bytes32(0)) revert ReferenciaVacia();
        if (monto == 0) revert MontoCero();
        // slither-disable-next-line timestamp
        if (block.timestamp > vence) revert PermisoVencido(vence);
        if (cobrado[referencia]) revert RetiroYaCobrado(referencia);
        bytes32 digest = digestDelRetiro(referencia, msg.sender, monto, vence);
        if (!SignatureChecker.isValidSignatureNowCalldata(firmante, digest, firma)) {
            revert FirmaInvalida();
        }
        if (monto > address(this).balance) revert SaldoInsuficiente(address(this).balance, monto);

        // Effects
        cobrado[referencia] = true;
        emit RetiroCobrado(referencia, msg.sender, monto);

        // Interactions
        (bool ok,) = payable(msg.sender).call{value: monto}("");
        if (!ok) revert TransferenciaFallida();
    }

    /// @notice El hash EIP-712 que firma el back para un retiro. Sirve para verificar desde
    /// afuera que el back y el contrato arman el mismo permiso.
    function digestDelRetiro(bytes32 referencia, address destino, uint256 monto, uint256 vence)
        public
        view
        returns (bytes32)
    {
        return
            _hashTypedDataV4(keccak256(abi.encode(TIPO_RETIRO, referencia, destino, monto, vence)));
    }

    /// @notice Cambia la cuenta que firma los permisos. Los permisos de la anterior dejan de valer.
    function cambiarFirmante(address nuevo) external onlyOwner {
        if (nuevo == address(0)) revert DireccionInvalida();
        emit FirmanteCambiado(firmante, nuevo);
        firmante = nuevo;
    }

    /// @notice Transfiere `monto` de los fondos que sobran a `destino`.
    function retirar(address payable destino, uint256 monto) external nonReentrant onlyOwner {
        if (destino == address(0)) revert DireccionInvalida();
        if (monto == 0) revert MontoCero();
        if (monto > address(this).balance) revert SaldoInsuficiente(address(this).balance, monto);
        emit FondosRetirados(destino, monto);
        (bool ok,) = destino.call{value: monto}("");
        if (!ok) revert TransferenciaFallida();
    }

    /// @notice Frena los cobros ante una emergencia, por ejemplo si se filtra la clave del
    /// firmante. El dueño puede seguir cambiando el firmante y retirando fondos.
    function pausar() external onlyOwner {
        _pause();
    }

    /// @notice Vuelve a aceptar cobros.
    function reanudar() external onlyOwner {
        _unpause();
    }

    /// @notice Siempre revierte: sin dueño, no se podría cambiar un firmante comprometido.
    /// Para cambiar de dueño se usa el traspaso en dos pasos.
    function renounceOwnership() public view override onlyOwner {
        revert RenunciaNoPermitida();
    }

    /// @notice Recibe el ETH con el que se pagan los retiros.
    receive() external payable {
        if (msg.value == 0) revert MontoCero();
        emit Fondeado(msg.sender, msg.value);
    }

    /// @dev Rechaza cualquier llamada desconocida, con o sin ETH.
    fallback() external payable {
        revert LlamadaDesconocida();
    }
}
