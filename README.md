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

## Contrato desplegado

| Red | Dirección | Explorador |
|---|---|---|
| Base Sepolia (84532) | `0x36e633eDD1E79Ef2b9A3c6A099D873D52e44EDF0` | [BaseScan](https://sepolia.basescan.org/address/0x36e633eDD1E79Ef2b9A3c6A099D873D52e44EDF0#code) (código verificado) |

El back y el front leen la dirección de la variable de entorno `PASARELA_CARGAS_ADDRESS`. En `deployments/base-sepolia.json` están la dirección, el chain id, el dueño, la transacción y el bloque del deploy, y el ABI.

Para integrarse con el contrato, el back tiene que leer el evento `CargaRegistrada` de los logs del recibo, filtrando por la dirección del contrato, y no mirar el `to` ni el `from` de la transacción. Una wallet con smart account (por ejemplo, MetaMask con transacciones delegadas) manda el pago a través de un relayer: el `to` y el `from` de la transacción son otros, pero el evento lo emite la pasarela con el pagador correcto.

Pago de prueba: [`0xc7412f41…87bd8`](https://sepolia.basescan.org/tx/0xc7412f41338eb0c815bbd3983b1bc3d4ffb8ac15e409c6a70475273654487bd8), desde MetaMask, con la referencia `keccak256("prueba-1")` y 0.0001 ETH.

## Deploy en Base Sepolia

El deploy es manual, desde la máquina de quien despliega, nunca desde el CI.

1. Importar la clave del deployer en un keystore cifrado de Foundry. La clave nunca va al `.env` ni al repo:

   ```sh
   cast wallet import deployer --interactive
   ```

2. Copiar `.env.example` a `.env` y completar el RPC de Base Sepolia, la API key v2 de Etherscan (sirve para BaseScan) y, si el dueño no es el deployer, `OWNER`.

3. Desplegar con verificación. `forge` lee solo el `.env` de la raíz del proyecto, así que no hace falta cargarlo antes (y en fish, `source .env` falla):

   ```sh
   forge script script/Deploy.s.sol --rpc-url base_sepolia --account deployer --broadcast --verify
   ```

   El script pide la contraseña del keystore. El dueño inicial es `OWNER` si está definida y no vacía, y si no, la cuenta `deployer`.

4. Actualizar `deployments/base-sepolia.json` y la tabla de [Contrato desplegado](#contrato-desplegado) con lo que deja `forge` en `broadcast/` (que no se commitea), y el ABI con `forge inspect PasarelaCargas abi --json`.

5. Si la verificación automática falla, verificar a mano:

   ```sh
   forge verify-contract <direccion> src/PasarelaCargas.sol:PasarelaCargas \
     --chain 84532 --constructor-args $(cast abi-encode "constructor(address)" <dueno>) --watch
   ```

## Ramas

Las ramas `PICA-xxx` salen de `dev` y los PRs van contra `dev`, que exige el CI en verde y una aprobación. `main` solo recibe entregas.
