#!/bin/bash

# Renk Tanımlamaları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
OG_PURPLE='\033[38;2;203;138;255m' # 0G Hex: #CB8AFF
NC='\033[0m' # No Color

set -o pipefail

fail() {
    echo -e "${RED}[✗] HATA: $1${NC}"
    exit 1
}

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
echo "        AUTOMATED GETH --> RETH MIGRATION VIA SNAPSHOT (v2 - fixed)     "
echo "========================================================================"
echo -e "${NC}"

# Profil Yükleme
[ -f $HOME/.bash_profile ] && source $HOME/.bash_profile

echo -e "${BLUE}[0/6] Gerekli bağımlılıklar kontrol ediliyor...${NC}"
echo "--------------------------------------------------"
REQUIRED_CMDS=("curl" "wget" "tar" "aria2c" "lz4" "jq")
declare -A PKG_NAME_MAP=( ["aria2c"]="aria2" )
MISSING_PKGS=()
for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        pkg="${PKG_NAME_MAP[$cmd]:-$cmd}"
        MISSING_PKGS+=("$pkg")
    fi
done
if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[!] Eksik paketler kuruluyor: ${MISSING_PKGS[*]}${NC}"
    sudo apt update -y &>/dev/null
    sudo apt install -y "${MISSING_PKGS[@]}" &>/dev/null || fail "Bağımlılıklar kurulamadı: ${MISSING_PKGS[*]}"
else
    echo -e "${GREEN}[✓] Tüm bağımlılıklar mevcut.${NC}"
fi
echo "--------------------------------------------------"
echo ""

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
[ -n "$PUBLIC_IP" ] || fail "Sunucu kamu IP'si alınamadı, ağ bağlantısını kontrol et."

echo "--------------------------------------------------"
echo -e "${GREEN}[✓] Yapılandırma Doğrulandı:${NC}"
echo -e "    Port Ön Eki: ${YELLOW}$OG_PORT${NC}"
echo -e "    ETH RPC URL: ${YELLOW}$ETH_RPC_URL${NC}"
echo -e "    Sunucu IP:   ${YELLOW}$PUBLIC_IP${NC}"
echo "--------------------------------------------------"
echo ""

DATA_DIR="$HOME/.0gchaind/0g-home/0gchaind-home/data"
PVS_FILE="$DATA_DIR/priv_validator_state.json"
PVS_BACKUP="$HOME/.0gchaind/priv_validator_state.json.backup"
PVS_WAS_BACKED_UP=0

# 1. ADIM: Snapshot Kaynağını Önceden Doğrula (VERİ SİLİNMEDEN ÖNCE!)
echo -e "${BLUE}[1/7] Snapshot sunucusu kontrol ediliyor (veri silinmeden önce doğrulama)...${NC}"
SNAPSHOT_URL="https://files.corenodehq.xyz/0g/snapshot/"
SNAPSHOT_LISTING=$(curl -sf "$SNAPSHOT_URL") || fail "Snapshot sunucusuna erişilemedi: $SNAPSHOT_URL"

LATEST_COSMOS=$(echo "$SNAPSHOT_LISTING" | grep -oP '0g_\d{8}-\d{4}_\d+_cosmos\.tar\.lz4' | sort | tail -n 1)
LATEST_RETH=$(echo "$SNAPSHOT_LISTING" | grep -oP '0g_\d{8}-\d{4}_\d+_reth\.tar\.lz4' | sort | tail -n 1)

if [ -z "$LATEST_COSMOS" ] || [ -z "$LATEST_RETH" ]; then
    fail "Snapshot sunucusunda geçerli dosya bulunamadı. Hiçbir yerel veri SİLİNMEDİ, güvenle çıkılıyor."
fi
echo -e "${GREEN}[✓] Snapshot dosyaları bulundu:${NC}"
echo -e "    Cosmos: ${YELLOW}$LATEST_COSMOS${NC}"
echo -e "    Reth:   ${YELLOW}$LATEST_RETH${NC}"

# 2. ADIM: Eski Servisleri Durdurma, Disable Etme ve Validator State Yedekleme
echo -e "${BLUE}[2/7] Eski servisler durduruluyor, Geth servisi pasifleştiriliyor...${NC}"
sudo systemctl stop 0gchaind geth reth 2>/dev/null
sudo systemctl disable geth 2>/dev/null
sudo rm -f /etc/systemd/system/geth.service 2>/dev/null

# Validator state yedeği — KRİTİK: başarısız olursa işlemi durdur (çifte imzalama riski)
if [ -f "$PVS_FILE" ]; then
    mv "$PVS_FILE" "$PVS_BACKUP" || fail "priv_validator_state.json yedeklenemedi! Çifte imzalama riski nedeniyle işlem durduruldu."
    PVS_WAS_BACKED_UP=1
    echo -e "${GREEN}[✓] priv_validator_state.json yedeklendi.${NC}"
else
    echo -e "${YELLOW}[!] priv_validator_state.json bulunamadı (yeni kurulum olabilir), yedekleme atlandı.${NC}"
fi

# 3. ADIM: Bağımlılık Paketleri ve Aristotle v1.0.6 Hazırlığı
echo -e "${BLUE}[3/7] Aristotle v1.0.6 binary'leri ve JWT yapılandırması yükleniyor...${NC}"

cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
[ -s aristotle.tar.gz ] || fail "Aristotle v1.0.6 indirilemedi (dosya boş veya yok)."

# Arşivin gerçek kök klasör adını dinamik yakala (büyük/küçük harf uyuşmazlığı riskini ortadan kaldırır)
EXTRACTED_DIR=$(tar -tzf aristotle.tar.gz | head -1 | cut -f1 -d"/")
[ -n "$EXTRACTED_DIR" ] || fail "Arşiv içeriği okunamadı."

tar -xzf aristotle.tar.gz -C $HOME || fail "Arşiv açılamadı."
rm -f aristotle.tar.gz
rm -rf $HOME/aristotle-used 2>/dev/null
mv "$HOME/$EXTRACTED_DIR" "$HOME/aristotle-used" || fail "Çıkarılan klasör '$EXTRACTED_DIR' bulunamadı/taşınamadı."

[ -f "$HOME/aristotle-used/bin/reth" ] && [ -f "$HOME/aristotle-used/bin/0gchaind" ] || fail "reth veya 0gchaind binary'leri paket içinde bulunamadı."

mkdir -p $HOME/go/bin
sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind

# Reth dizini ve gerekli auth dosyaları
mkdir -p $HOME/.0gchaind/0g-home/reth-home
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/

echo -e "${GREEN}[✓] Aristotle binary'leri ve JWT/KZG dosyaları yerleştirildi (klasör: $EXTRACTED_DIR).${NC}"

# 4. ADIM: Eski Verileri Silme ve Temizlik (artık snapshot doğrulandıktan SONRA)
echo -e "${BLUE}[4/7] Eski Geth ve Cosmos verileri temizleniyor...${NC}"
rm -rf $HOME/.0gchaind/0g-home/geth-home
rm -rf $HOME/.0gchaind/0g-home/0gchaind-home/data
rm -rf $HOME/.0gchaind/0g-home/reth-home/db
rm -rf $HOME/.0gchaind/0g-home/reth-home/static_files

# 5. ADIM: Snapshot İndirme ve Kurulum (indirme bütünlüğü kontrol edilerek)
echo -e "${BLUE}[5/7] Corenode Snapshot sunucusundan güncel paketler indiriliyor...${NC}"

COSMOS_URL="${SNAPSHOT_URL}${LATEST_COSMOS}"
RETH_URL="${SNAPSHOT_URL}${LATEST_RETH}"

echo -e "${CYAN}Cosmos verisi indiriliyor...${NC}"
aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_COSMOS" "$COSMOS_URL" \
    || fail "Cosmos snapshot indirilemedi."
[ -s "/tmp/$LATEST_COSMOS" ] || fail "Cosmos snapshot dosyası boş/yok."

mkdir -p $HOME/.0gchaind/0g-home/0gchaind-home
lz4 -dc "/tmp/$LATEST_COSMOS" | tar -xf - -C $HOME/.0gchaind/0g-home/0gchaind-home \
    || fail "Cosmos snapshot çıkartılamadı (bozuk arşiv olabilir)."
rm -f "/tmp/$LATEST_COSMOS"

echo -e "${CYAN}Reth verisi indiriliyor...${NC}"
aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_RETH" "$RETH_URL" \
    || fail "Reth snapshot indirilemedi."
[ -s "/tmp/$LATEST_RETH" ] || fail "Reth snapshot dosyası boş/yok."

lz4 -dc "/tmp/$LATEST_RETH" | tar -xf - -C $HOME/.0gchaind/0g-home/reth-home \
    || fail "Reth snapshot çıkartılamadı (bozuk arşiv olabilir)."
rm -f "/tmp/$LATEST_RETH"

echo -e "${GREEN}[✓] Snapshot'lar başarıyla açıldı ve entegre edildi.${NC}"

# Validator state dosyasını geri yükle — KRİTİK: başarısız olursa 0gchaind BAŞLATILMAMALI
mkdir -p "$DATA_DIR"
if [ "$PVS_WAS_BACKED_UP" -eq 1 ]; then
    mv "$PVS_BACKUP" "$PVS_FILE" || fail "priv_validator_state.json GERİ YÜKLENEMEDİ! 0gchaind'i başlatma — çifte imzalama riski var. Manuel müdahale gerekiyor: $PVS_BACKUP"
    echo -e "${GREEN}[✓] priv_validator_state.json geri yüklendi (orijinal imzalama geçmişi korundu).${NC}"
else
    echo -e "${YELLOW}[!] Geri yüklenecek bir priv_validator_state.json yedeği yoktu, snapshot'ın kendi dosyası kullanılacak.${NC}"
fi

# 6. ADIM: Systemd Servis Dosyalarının Yenilenmesi
echo -e "${BLUE}[6/7] Systemd servis yapılandırmaları yazılıyor...${NC}"

CONFIG_FILE="$HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml"
if grep -q "^rpc-dial-url" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" "$CONFIG_FILE"
else
    echo -e "${YELLOW}[!] UYARI: '$CONFIG_FILE' içinde 'rpc-dial-url' satırı bulunamadı, manuel kontrol et.${NC}"
fi

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

# 7. ADIM: Başlatma ve Doğrulama
echo -e "${BLUE}[7/7] Yeni Reth ve Consensus servisleri tetikleniyor...${NC}"
sudo systemctl start reth
sleep 5
if ! sudo systemctl is-active --quiet reth; then
    echo -e "${RED}[✗] reth servisi başlatılamadı! Loglar: sudo journalctl -u reth -n 50 --no-pager${NC}"
fi

sudo systemctl start 0gchaind
sleep 5
if ! sudo systemctl is-active --quiet 0gchaind; then
    echo -e "${RED}[✗] 0gchaind servisi başlatılamadı! Loglar: sudo journalctl -u 0gchaind -n 50 --no-pager${NC}"
fi

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
