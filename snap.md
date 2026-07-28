#!/bin/bash

# Servisleri durdur
sudo systemctl stop 0gchaind reth

# Validator state dosyasını korumaya al
mv $HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json $HOME/.0gchaind/priv_validator_state.json.backup 2>/dev/null || true

# Eski Cosmos ve Reth veri dizinlerini temizle
rm -rf $HOME/.0gchaind/0g-home/0gchaind-home/data
rm -rf $HOME/.0gchaind/0g-home/reth-home/db
rm -rf $HOME/.0gchaind/0g-home/reth-home/static_files

# Reth hedef klasörünü garantiye al
mkdir -p $HOME/.0gchaind/0g-home/reth-home

SNAPSHOT_URL="https://files.corenodehq.xyz/0g/snapshot/"
LATEST_COSMOS=$(curl -s $SNAPSHOT_URL | grep -oP '0g_\d{8}-\d{4}_\d+_cosmos\.tar\.lz4' | sort | tail -n 1)
LATEST_RETH=$(curl -s $SNAPSHOT_URL | grep -oP '0g_\d{8}-\d{4}_\d+_reth\.tar\.lz4' | sort | tail -n 1)

if [ -n "$LATEST_COSMOS" ] && [ -n "$LATEST_RETH" ]; then
  COSMOS_URL="${SNAPSHOT_URL}${LATEST_COSMOS}"
  RETH_URL="${SNAPSHOT_URL}${LATEST_RETH}"

  if curl -s --head "$COSMOS_URL" | head -n 1 | grep "200" > /dev/null && \
     curl -s --head "$RETH_URL" | head -n 1 | grep "200" > /dev/null; then

    echo "Cosmos Snapshot indiriliyor ve açılıyor..."
    aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_COSMOS" "$COSMOS_URL"
    lz4 -dc /tmp/"$LATEST_COSMOS" | tar -xf - -C $HOME/.0gchaind/0g-home/0gchaind-home
    rm -f /tmp/"$LATEST_COSMOS"
    
    echo "Reth Snapshot indiriliyor ve açılıyor..."
    aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_RETH" "$RETH_URL"
    lz4 -dc /tmp/"$LATEST_RETH" | tar -xf - -C $HOME/.0gchaind/0g-home/reth-home
    rm -f /tmp/"$LATEST_RETH"

    # Priv validator state dosyasını geri yükle
    mv $HOME/.0gchaind/priv_validator_state.json.backup $HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json 2>/dev/null || true

    # Servisleri başlat
    sudo systemctl restart reth
    sleep 5
    sudo systemctl restart 0gchaind

    # Logları canlı takip et
    sudo journalctl -u reth -u 0gchaind -f -o cat
  else
    echo "Snapshot URL is not accessible"
  fi
else
  echo "No snapshot found"
fi
