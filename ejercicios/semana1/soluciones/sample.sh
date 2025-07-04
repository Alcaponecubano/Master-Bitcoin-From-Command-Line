#!/bin/bash
set -euo pipefail

# ========================================
# Script  para nodo Bitcoin en regtest
# Autor: Daniel Fabian Quesada @alcaponecubano
# ========================================

BITCOIN_VERSION="29.0"
INSTALL_DIR="$HOME/bitcoin"
CONF_DIR="$HOME/.bitcoin"
CONF_FILE="$CONF_DIR/bitcoin.conf"
WALLET_MINER="Miner"
WALLET_TRADER="Trader"
BITCOIN_BIN="$INSTALL_DIR/bitcoin-${BITCOIN_VERSION}/bin"
WALLET_PATH="$CONF_DIR/regtest/wallets"

# 1. Verificar dependencias
for pkg in wget jq tar; do
    if ! command -v $pkg &> /dev/null; then
        echo "Error: el paquete '$pkg' no está instalado. Instálelo: sudo apt install $pkg"
        exit 1
    fi
done

# 2. Detener instancia previa de bitcoind (ignorar error de cookie)
if pgrep -x "bitcoind" > /dev/null; then
    echo "Deteniendo bitcoind existente..."
    "$BITCOIN_BIN/bitcoin-cli" -regtest stop || echo "No se pudo detener vía RPC; matando proceso..."
    pkill bitcoind || true
    sleep 3
fi

# 3. Limpiar wallets previas
if [ -d "$WALLET_PATH/$WALLET_MINER" ] || [ -d "$WALLET_PATH/$WALLET_TRADER" ]; then
    echo "Eliminando wallets previas: $WALLET_MINER y $WALLET_TRADER"
    rm -rf "$WALLET_PATH/$WALLET_MINER" "$WALLET_PATH/$WALLET_TRADER"
fi

# 4. Configurar bitcoin.conf
echo "Configurando bitcoin.conf en $CONF_FILE"
mkdir -p "$CONF_DIR"
cat > "$CONF_FILE" << EOF
regtest=1
fallbackfee=0.0001
server=1
txindex=1
EOF

# 5. Descargar e instalar binarios si no existen
echo "Descargando Bitcoin Core v$BITCOIN_VERSION si es necesario..."
mkdir -p "$INSTALL_DIR"
cd "$INSTALL_DIR"
if [ ! -d "$INSTALL_DIR/bitcoin-${BITCOIN_VERSION}" ]; then
    wget -q "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
    wget -q "https://bitcoincore.org/bin/bitcoin-core-${BITCOIN_VERSION}/SHA256SUMS"
    sha256sum --ignore-missing --check SHA256SUMS
    tar -xzf "bitcoin-${BITCOIN_VERSION}-x86_64-linux-gnu.tar.gz"
fi

# 6. Iniciar nodo
"$BITCOIN_BIN/bitcoind" -daemon
sleep 5

# 7. Crear wallets Miner y Trader
echo "Creando wallets"
"$BITCOIN_BIN/bitcoin-cli" -regtest createwallet "$WALLET_MINER"
"$BITCOIN_BIN/bitcoin-cli" -regtest createwallet "$WALLET_TRADER"

# 8. Minar bloques para saldo maduro
echo "Minando bloques para saldo maduro"
MINER_ADDR=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" getnewaddress "Recompensa de Mineria")
"$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" generatetoaddress 200 "$MINER_ADDR"

# 9. Mostrar saldo de Miner
MINER_BALANCE=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" getbalance)
echo "Saldo Miner: $MINER_BALANCE BTC"

# 10. Crear dirección Trader y enviar BTC
echo "Enviando 20 BTC de Miner a Trader"
TRADER_ADDR=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_TRADER" getnewaddress "Recibido")
TXID=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" sendtoaddress "$TRADER_ADDR" 20)
echo "TXID: $TXID"

# 11. Verificar en mempool
"$BITCOIN_BIN/bitcoin-cli" -regtest getmempoolentry "$TXID"

# 12. Confirmar transacción
"$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" generatetoaddress 1 "$MINER_ADDR"

# 13. Obtener detalles de la transacción
TX_RAW=$("$BITCOIN_BIN/bitcoin-cli" -regtest getrawtransaction "$TXID")
TX_DECODED=$("$BITCOIN_BIN/bitcoin-cli" -regtest decoderawtransaction "$TX_RAW")
TX_DATA=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" gettransaction "$TXID")
INPUT_TXID=$(echo "$TX_DECODED" | jq -r '.vin[0].txid')
OUTPUTS=$(echo "$TX_DECODED" | jq -c '.vout')
FEE=$(echo "$TX_DATA" | jq '.fee')
BLOCKHASH=$(echo "$TX_DATA" | jq -r '.blockhash')
BLOCK_HEIGHT=$("$BITCOIN_BIN/bitcoin-cli" -regtest getblock "$BLOCKHASH" | jq '.height')
BAL_MINER=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_MINER" getbalance)
BAL_TRADER=$("$BITCOIN_BIN/bitcoin-cli" -regtest -rpcwallet="$WALLET_TRADER" getbalance)

# 14. Mostrar resumen
cat << EOF
=== Resumen de la Transacción ===
TXID: $TXID
Entrada TX: $INPUT_TXID
Salidas: $OUTPUTS
Comisión: $FEE BTC
Bloque: Altura $BLOCK_HEIGHT
Saldo Miner: $BAL_MINER BTC
Saldo Trader: $BAL_TRADER BTC
===================================
EOF

 echo "Script completado sin errores."