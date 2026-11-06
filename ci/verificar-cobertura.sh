#!/usr/bin/env bash
# Falla si las líneas o las ramas de los contratos de producción (src/) quedan por debajo del
# mínimo. Lee el lcov que genera `forge coverage --report lcov`.
set -euo pipefail

archivo="${1:-lcov.info}"
minimo="${COBERTURA_MINIMA:-90}"

awk -v minimo="$minimo" '
  /^SF:/ { en_src = ($0 ~ /^SF:src\//) }
  en_src && /^LF:/  { lf  += substr($0, 4) }
  en_src && /^LH:/  { lh  += substr($0, 4) }
  en_src && /^BRF:/ { brf += substr($0, 5) }
  en_src && /^BRH:/ { brh += substr($0, 5) }
  END {
    if (lf == 0) { print "No hay líneas de src/ en el reporte de cobertura"; exit 1 }
    lineas = 100 * lh / lf
    ramas = (brf == 0) ? 100 : 100 * brh / brf
    printf "Cobertura de src/: líneas %.2f %% (%d/%d), ramas %.2f %% (%d/%d), mínimo %d %%\n", lineas, lh, lf, ramas, brh, brf, minimo
    if (lineas < minimo || ramas < minimo) { print "La cobertura está por debajo del mínimo"; exit 1 }
  }
' "$archivo"
