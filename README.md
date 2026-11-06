# pica-contracts

Contrato de la pasarela de cargas de PICA. Un usuario paga con ETH de prueba la carga de saldo que inició en la plataforma, y el contrato deja un registro verificable en la blockchain que el back usa para acreditar la carga en su billetera.

Red: Base Sepolia. Herramientas: [Foundry](https://getfoundry.sh), Solidity 0.8.38 y OpenZeppelin Contracts v5.7.0.

## Cómo funciona

1. El back genera la **referencia** de la carga (un `bytes32`) y la guarda como pendiente, con el monto en pesos.
2. El usuario llama a `cargar(referencia)` desde su wallet, enviando el ETH.
3. El contrato marca la referencia como pagada y emite `CargaRegistrada(referencia, pagador, monto)`.
4. El back lee ese evento en el recibo de la transacción, verifica el monto con la cotización fija y acredita la carga.

El contrato registra el monto en wei y no sabe nada de pesos: la cotización y la verificación del monto esperado son del back.

## Interfaz de `PasarelaCargas`

| Función | Quién | Con el contrato pausado | Qué hace |
|---|---|---|---|
| `cargar(bytes32 referencia)` payable | cualquiera | revierte | Registra el pago y emite `CargaRegistrada` |
| `retirar(address destino, uint256 monto)` | dueño | funciona | Transfiere `monto` a `destino` y emite `FondosRetirados` |
| `pausar()` / `reanudar()` | dueño | — | Frena o vuelve a aceptar los pagos |
| `pagada(bytes32 referencia)` | cualquiera | — | Indica si la referencia ya se pagó |
| `transferOwnership` / `acceptOwnership` | dueño / nuevo dueño | — | Traspaso del contrato en dos pasos |
| `renounceOwnership()` | dueño | — | Siempre revierte: sin dueño, lo recaudado quedaría bloqueado |

Eventos:

- `CargaRegistrada(bytes32 indexed referencia, address indexed pagador, uint256 monto)`
- `FondosRetirados(address indexed destino, uint256 monto)`
- `Paused`, `Unpaused` y los del traspaso de dueño, de OpenZeppelin

Errores:

| Error | Cuándo |
|---|---|
| `MontoCero()` | Una carga o un retiro de 0 |
| `ReferenciaVacia()` | Una carga con la referencia `0x0` |
| `ReferenciaYaPagada(referencia)` | Una carga a una referencia que ya se pagó |
| `PagoSinReferencia()` | ETH enviado al contrato sin pasar por `cargar` |
| `DestinoInvalido()` | Un retiro a la dirección cero |
| `SaldoInsuficiente(saldo, monto)` | Un retiro mayor que el saldo |
| `TransferenciaFallida()` | El destino del retiro rechazó el ETH |
| `RenunciaNoPermitida()` | El dueño intenta renunciar al contrato |

Seguridad: `Ownable2Step`, `Pausable` y `ReentrancyGuard` de OpenZeppelin, y el patrón checks-effects-interactions en `retirar`. El contrato no es actualizable.

## Desarrollo

Requisitos: Foundry (`foundryup`) y, para el análisis estático, [Slither](https://github.com/crytic/slither) (`pipx install slither-analyzer`).

```sh
git clone --recurse-submodules https://github.com/hydra-sip/pica-contracts.git
cd pica-contracts

forge build
forge test                     # perfil por defecto, rápido
FOUNDRY_PROFILE=ci forge test  # 1000 casos de fuzz y 256 corridas de invariantes, como el CI
forge fmt
```

### Cobertura

```sh
forge coverage --report summary --report lcov --no-match-coverage '^(test|script)/'
./ci/verificar-cobertura.sh lcov.info
```

El CI exige al menos el 90 % de líneas y de ramas sobre `src/`.

### Slither

```sh
slither . --filter-paths "lib/|test/|script/" --fail-medium
```

El CI falla con cualquier hallazgo Medium o High. Si aparece un falso positivo, se suprime en la línea con `// slither-disable-next-line <detector>` y un comentario que explique por qué, y se menciona en el PR.

## Deploy en Base Sepolia

El deploy es manual, desde la máquina de quien despliega, nunca desde el CI.

1. Importar la clave del deployer en un keystore cifrado de Foundry. La clave nunca va al `.env` ni al repo:

   ```sh
   cast wallet import deployer --interactive
   ```

2. Copiar `.env.example` a `.env` y completar el RPC de Base Sepolia, la API key v2 de Etherscan (sirve para BaseScan) y, si el dueño no es el deployer, `OWNER`.

3. Cargar las variables y desplegar con verificación:

   ```sh
   source .env
   forge script script/Deploy.s.sol --rpc-url base_sepolia --account deployer --broadcast --verify
   ```

   El script pide la contraseña del keystore. El dueño inicial es `OWNER` si está definida y no vacía, y si no, la cuenta `deployer`.

4. Si la verificación automática falla, verificar a mano:

   ```sh
   forge verify-contract <direccion> src/PasarelaCargas.sol:PasarelaCargas \
     --chain 84532 --constructor-args $(cast abi-encode "constructor(address)" <dueno>) --watch
   ```

## Ramas

Las ramas `PICA-xxx` salen de `dev` y los PRs van contra `dev`, que exige el CI en verde y una aprobación. `main` solo recibe entregas.
