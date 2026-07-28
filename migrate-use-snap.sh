#!/bin/bash

# Renk Tanımlamaları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
OG_PURPLE='\033[38;2;203;138;255m' # 0G Hex: #CB8AFF
NC='\033[0m' # No Color

# Ekranı Temizle ve Corenode Logosunu Bas
clear
echo -e "${CYAN}"
echo "========================================================================"
echo " ▄████████  ▄██████▄     ▄████████    ▄████████     ███▄▄▄▄     ▄██████▄  ████████▄     ▄████████ "
echo "███    ███ ███    ███   ███    ███   ███    ███     ███▀▀▀██▄  ███    ███ ███    ▀███   ███    ███ "
echo "███    █▀  ███    ███   ███    ███   ███    █▀      ███    ███ ███    ███ ███     ███   ███    █▀  "
echo "███        ███    ███  ▄███▄▄▄▄██▀  ▄███▄▄▄         ███    ███ ███    ███ ███     ███  ▄███▄▄▄     "
echo "███        ███    ███ ▀▀███▀▀▀▀▀   ▀▀███▀▀▀         ███    ███ ███    ███ ███     ███ ▀▀███▀▀▀     "
echo "███    █▄  ███    ███ ▀███████████   ███    █▄      ███    ███ ███    ███ ███     ███   ███    █▄  "
echo "███    ███ ███    ███   ███    ███   ███    ███     ███    ███ ███    ███ ███    ▄███   ███    ███ "
echo "████████▀   ▀██████▀    ███    ███   ██████████      ▀█    █▀   ▀██████▀  ████████▀    ██████████ "
echo "                        ███    ███                                                              "
echo "                                                                                                "
echo "           AUTOMATED GETH --> RETH MIGRATION VIA SNAPSHOT               "
echo "========================================================================"
echo -e "${NC}"

# Profil Yükleme
[ -f $HOME/.bash_profile ] && source $HOME/.bash_profile

echo -e "${BLUE}[>] Port ve RPC Yapılandırması Kontrol Ediliyor...${NC}"
echo "--------------------------------------------------"

# 1. OG_PORT SORGUSU
if [ -z "$OG_PORT" ]; then
    read -p "Lütfen OG_PORT ön ekini giriniz (Örn: 59): " INPUT_PORT
    while [ -z "$INPUT_PORT" ]; do
        read -p "OG_PORT boş bırakılamaz! Lütfen giriniz: " INPUT_PORT
    done
    export OG_PORT=$INPUT_PORT
    echo "export OG_PORT=\"$OG_PORT\"" >> $HOME/.bash_profile
else
    read -p "Mevcut OG_PORT [$OG_PORT] (Değiştirmek için yeni değer girin, ENTER ile geçin): " INPUT_PORT
    if [ -n "$INPUT_PORT" ]; then
        export OG_PORT=$INPUT_PORT
        sed -i "s|^export OG_PORT=.*|export OG_PORT=\"$OG_PORT\"|" $HOME/.bash_profile
    fi
fi

# 2. ETH_RPC_URL SORGUSU
if [ -z "$ETH_RPC_URL" ]; then
    read -p "Lütfen Ethereum Mainnet RPC URL adresini giriniz: " INPUT_RPC
    while [ -z "$INPUT_RPC" ]; do
        read -p "ETH_RPC_URL boş bırakılamaz! Lütfen giriniz: " INPUT_RPC
    done
    export ETH_RPC_URL=$INPUT_RPC
    echo "export ETH_RPC_URL=\"$ETH_RPC_URL\"" >> $HOME/.bash_profile
else
    read -p "Mevcut ETH_RPC_URL [$ETH_RPC_URL] (Değiştirmek için yeni URL girin, ENTER ile geçin): " INPUT_RPC
    if [ -n "$INPUT_RPC" ]; then
        export ETH_RPC_URL=$INPUT_RPC
        sed -i "s|^export ETH_RPC_URL=.*|export ETH_RPC_URL=\"$ETH_RPC_URL\"|" $HOME/.bash_profile
    fi
fi

source $HOME/.bash_profile

# Sunucu Kamu IP'sini Al
PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com)

echo "--------------------------------------------------"
echo -e "${GREEN}[✓] Yapılandırma Doğrulandı:${NC}"
echo -e "    Port Ön Eki: ${YELLOW}$OG_PORT${NC}"
echo -e "    ETH RPC URL: ${YELLOW}$ETH_RPC_URL${NC}"
echo -e "    Sunucu IP:   ${YELLOW}$PUBLIC_IP${NC}"
echo "--------------------------------------------------"
echo ""

# 1. ADIM: Eski Servisleri Durdurma, Disable Etme ve State Yedekleme
echo -e "${BLUE}[1/6] Eski servisler durduruluyor, Geth servisi pasifleştiriliyor...${NC}"
sudo systemctl stop 0gchaind geth reth 2>/dev/null
sudo systemctl disable geth 2>/dev/null
sudo rm -f /etc/systemd/system/geth.service 2>/dev/null

# Validator state yedeği
mv $HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json $HOME/.0gchaind/priv_validator_state.json.backup 2>/dev/null || true

# 2. ADIM: Bağımlılık Paketleri ve Aristotle v1.0.6 Hazırlığı
echo -e "${BLUE}[2/6] Aristotle v1.0.6 binary'leri ve JWT yapılandırması yükleniyor...${NC}"
sudo apt update && sudo apt install aria2 lz4 jq -y &>/dev/null

cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz &>/dev/null
tar -xzvf aristotle.tar.gz -C $HOME &>/dev/null
rm -rf aristotle.tar.gz
rm -rf $HOME/aristotle-used 2>/dev/null
mv $HOME/Aristotle-v1.0.6 $HOME/aristotle-used

mkdir -p $HOME/go/bin
sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind

# Reth dizini ve gerekli auth dosyaları
mkdir -p $HOME/.0gchaind/0g-home/reth-home
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/

echo -e "${GREEN}[✓] Aristotle binary'leri ve JWT/KZG dosyaları yerleştirildi.${NC}"

# 3. ADIM: Eski Verileri Silme ve Temizlik
echo -e "${BLUE}[3/6] Eski Geth ve Cosmos verileri temizleniyor...${NC}"
rm -rf $HOME/.0gchaind/0g-home/geth-home
rm -rf $HOME/.0gchaind/0g-home/0gchaind-home/data
rm -rf $HOME/.0gchaind/0g-home/reth-home/db
rm -rf $HOME/.0gchaind/0g-home/reth-home/static_files

# 4. ADIM: Snapshot İndirme ve Kurulum
echo -e "${BLUE}[4/6] Corenode Snapshot sunucusundan güncel paketler indiriliyor...${NC}"

SNAPSHOT_URL="https://files.corenodehq.xyz/0g/snapshot/"
LATEST_COSMOS=$(curl -s $SNAPSHOT_URL | grep -oP '0g_\d{8}-\d{4}_\d+_cosmos\.tar\.lz4' | sort | tail -n 1)
LATEST_RETH=$(curl -s $SNAPSHOT_URL | grep -oP '0g_\d{8}-\d{4}_\d+_reth\.tar\.lz4' | sort | tail -n 1)

if [ -n "$LATEST_COSMOS" ] && [ -n "$LATEST_RETH" ]; then
    echo -e "${YELLOW}[>] Cosmos Snapshot: $LATEST_COSMOS${NC}"
    echo -e "${YELLOW}[>] Reth Snapshot:   $LATEST_RETH${NC}"

    COSMOS_URL="${SNAPSHOT_URL}${LATEST_COSMOS}"
    RETH_URL="${SNAPSHOT_URL}${LATEST_RETH}"

    echo -e "${CYAN}Cosmos verisi indiriliyor ve çıkartılıyor...${NC}"
    aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_COSMOS" "$COSMOS_URL"
    lz4 -dc /tmp/"$LATEST_COSMOS" | tar -xf - -C $HOME/.0gchaind/0g-home/0gchaind-home
    rm -f /tmp/"$LATEST_COSMOS"

    echo -e "${CYAN}Reth verisi indiriliyor ve çıkartılıyor...${NC}"
    aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_RETH" "$RETH_URL"
    lz4 -dc /tmp/"$LATEST_RETH" | tar -xf - -C $HOME/.0gchaind/0g-home/reth-home
    rm -f /tmp/"$LATEST_RETH"

    # Validator state dosyasını geri yükle
    mv $HOME/.0gchaind/priv_validator_state.json.backup $HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json 2>/dev/null || true
    echo -e "${GREEN}[✓] Snapshot'lar başarıyla açıldı ve entegre edildi.${NC}"
else
    echo -e "${RED}[!] HATA: Snapshot sunucusunda geçerli dosya bulunamadı! İşlem iptal ediliyor.${NC}"
    exit 1
fi

# 5. ADIM: Systemd Servis Dosyalarının Yenilenmesi
echo -e "${BLUE}[5/6] Systemd servis yapılandırmaları yazılıyor...${NC}"

sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml 2>/dev/null

# Reth Servisi
sudo tee /etc/systemd/system/reth.service > /dev/null <<SEVEOF
[Unit]
Description=0G Labs Reth Execution Client
After=network.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/aristotle-used
ExecStart=$HOME/go/bin/reth node \
  --chain $HOME/aristotle-used/geth-genesis.json \
  --http \
  --http.addr 0.0.0.0 \
  --http.port ${OG_PORT}545 \
  --http.api eth,net,admin \
  --authrpc.addr 0.0.0.0 \
  --authrpc.port ${OG_PORT}551 \
  --authrpc.jwtsecret $HOME/.0gchaind/0g-home/jwt.hex \
  --datadir $HOME/.0gchaind/0g-home/reth-home \
  --ipcpath $HOME/.0gchaind/0g-home/reth-home/eth-engine.ipc \
  --engine.persistence-threshold 0 \
  --engine.memory-block-buffer-target 0 \
  --bootnodes="enode://2bf74c837a98c94ad0fa8f5c58a428237d2040f9269fe622c3dbe4fef68141c28e2097d7af6ebaa041194257543dc112514238361a6498f9a38f70fd56493f96@8.221.140.134:30303" \
  --port ${OG_PORT}303 \
  --nat extip:${PUBLIC_IP}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SEVEOF

# Consensus Servisi
sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<SEVEOF
[Unit]
Description=0GChainD Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/aristotle-used
ExecStart=$HOME/go/bin/0gchaind start \
  --rpc.laddr tcp://0.0.0.0:${OG_PORT}657 \
  --chaincfg.chain-spec mainnet \
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/0g-home/kzg-trusted-setup.json \
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/0g-home/jwt.hex \
  --chaincfg.block-store-service.enabled \
  --chaincfg.block-store-service.availability-window=1000 \
  --chaincfg.node-api.enabled \
  --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \
  --pruning=everything \
  --min-retain-blocks=10000 \
  --chaincfg.restaking.enabled \
  --chaincfg.restaking.symbiotic-rpc-dial-url $ETH_RPC_URL \
  --chaincfg.restaking.symbiotic-get-logs-block-range 1 \
  --home=$HOME/.0gchaind/0g-home/0gchaind-home \
  --p2p.external_address=${PUBLIC_IP}:${OG_PORT}656
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SEVEOF

sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
echo -e "${GREEN}[✓] Servis dosyaları güncellendi ve aktif edildi.${NC}"

# 6. ADIM: Başlatma ve Kapanış
echo -e "${BLUE}[6/6] Yeni Reth ve Consensus servisleri tetikleniyor...${NC}"
sudo systemctl start reth
sleep 3
sudo systemctl start 0gchaind

echo -e "${GREEN}========================================================================"
echo -e "   [✓] MIGRATION VE SNAPSHOT KURULUMU BAŞARIYLA TAMAMLANDI! [✓]   "
echo -e "========================================================================${NC}"
echo -e "${OG_PURPLE}"
cat << "EOF"
      ████████        ████████   
    ███  ██  ███    ███      ███ 
   ███  ██    ███  ███           
   ███ ██     ███  ███   ████████
   █████      ███  ███        ███
    ███      ███    ███      ███ 
      ████████        ████████   

              WE ARE 0G
EOF
echo -e "${NC}"
echo -e "${YELLOW}Logları anlık izlemek için:${NC}"
echo -e "    Reth Logları:      ${CYAN}sudo journalctl -u reth -f -o cat${NC}"
echo -e "    Consensus Logları: ${CYAN}sudo journalctl -u 0gchaind -f -o cat${NC}"
echo ""
