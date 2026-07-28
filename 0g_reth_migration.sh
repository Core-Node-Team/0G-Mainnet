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
echo "                FULLY INTERACTIVE GETH --> RETH MIGRATION (v2 - fixed)   "
echo "========================================================================"
echo -e "${NC}"

# Hata durumunda scripti durdur (kritik komutlar ayrıca da kontrol ediliyor)
set -o pipefail

fail() {
    echo -e "${RED}[✗] HATA: $1${NC}"
    exit 1
}

# Profil Yükleme
[ -f $HOME/.bash_profile ] && source $HOME/.bash_profile

echo -e "${BLUE}[0/8] Gerekli bağımlılıklar kontrol ediliyor...${NC}"
echo "--------------------------------------------------"
REQUIRED_CMDS=("jq" "screen" "curl" "wget" "tar" "python3" "bc")
declare -A PKG_NAME_MAP=( ["python3"]="python3" )
MISSING_PKGS=()

for cmd in "${REQUIRED_CMDS[@]}"; do
    if ! command -v "$cmd" &>/dev/null; then
        pkg="${PKG_NAME_MAP[$cmd]:-$cmd}"
        MISSING_PKGS+=("$pkg")
    fi
done

if [ ${#MISSING_PKGS[@]} -gt 0 ]; then
    echo -e "${YELLOW}[!] Eksik paketler bulundu, kuruluyor: ${MISSING_PKGS[*]}${NC}"
    sudo apt update -y &>/dev/null
    sudo apt install -y "${MISSING_PKGS[@]}" &>/dev/null || fail "Bağımlılıklar kurulamadı: ${MISSING_PKGS[*]}"
    echo -e "${GREEN}[✓] Eksik paketler kuruldu.${NC}"
else
    echo -e "${GREEN}[✓] Tüm bağımlılıklar zaten mevcut.${NC}"
fi

mkdir -p $HOME/go/bin

if [ ! -f "$HOME/go/bin/geth" ]; then
    fail "$HOME/go/bin/geth bulunamadı. Mevcut geth binary'sinin bu yolda olduğundan emin ol."
fi
echo "--------------------------------------------------"
echo ""

# 1. OG_PORT VARYASYONU VE SORGUSU
if [ -z "$OG_PORT" ]; then
    read -p "Lütfen OG_PORT ön ekini giriniz (Örn: 59): " INPUT_PORT
    while [ -z "$INPUT_PORT" ]; do
        read -p "OG_PORT boş bırakılamaz! Lütfen giriniz: " INPUT_PORT
    done
    export OG_PORT=$INPUT_PORT
    echo "export OG_PORT=\"$OG_PORT\"" >> $HOME/.bash_profile
else
    read -p "Mevcut OG_PORT [$OG_PORT] (Değiştirmek için yeni değer girin, ENTER ile geçin): " INPUT_PORT
    if [ ! -z "$INPUT_PORT" ]; then
        export OG_PORT=$INPUT_PORT
        sed -i "s|^export OG_PORT=.*|export OG_PORT=\"$OG_PORT\"|" $HOME/.bash_profile
    fi
fi

# 2. ETH_RPC_URL VARYASYONU VE SORGUSU
if [ -z "$ETH_RPC_URL" ]; then
    read -p "Lütfen Ethereum Mainnet RPC URL adresini giriniz: " INPUT_RPC
    while [ -z "$INPUT_RPC" ]; do
        read -p "ETH_RPC_URL boş bırakılamaz! Lütfen giriniz: " INPUT_RPC
    done
    export ETH_RPC_URL=$INPUT_RPC
    echo "export ETH_RPC_URL=\"$ETH_RPC_URL\"" >> $HOME/.bash_profile
else
    read -p "Mevcut ETH_RPC_URL [$ETH_RPC_URL] (Değiştirmek için yeni URL girin, ENTER ile geçin): " INPUT_RPC
    if [ ! -z "$INPUT_RPC" ]; then
        export ETH_RPC_URL=$INPUT_RPC
        sed -i "s|^export ETH_RPC_URL=.*|export ETH_RPC_URL=\"$ETH_RPC_URL\"|" $HOME/.bash_profile
    fi
fi

# Değişkenleri Sisteme Yeniden Tanıt ve Teyit Et
source $HOME/.bash_profile

echo "--------------------------------------------------"
echo -e "${GREEN}[✓] Yapılandırma Kaydedildi ve Doğrulandı:${NC}"
echo -e "    Kullanılan Port Ön Eki: ${YELLOW}$OG_PORT${NC}"
echo -e "    Kullanılan ETH RPC URL: ${YELLOW}$ETH_RPC_URL${NC}"
echo "--------------------------------------------------"
echo ""

# 1. ADIM: Canlı Blok Yüksekliğini Otomatik Al ve Hafızaya At
echo -e "${BLUE}[1/8] Canlı ağ üzerinden güncel blok yüksekliği çekiliyor...${NC}"
export CHAIN_HEAD=$(curl -s -X POST http://localhost:${OG_PORT}545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf "%d\n" 2>/dev/null)

if [ -z "$CHAIN_HEAD" ] || [ "$CHAIN_HEAD" -eq 0 ] 2>/dev/null; then
    echo -e "${YELLOW}[!] UYARI: Canlı node RPC portundan veri alınamadı.${NC}"
    read -p "Lütfen ihraç edilecek son blok numarasını manuel girin: " CHAIN_HEAD
    while [ -z "$CHAIN_HEAD" ]; do
        read -p "Blok numarası boş bırakılamaz: " CHAIN_HEAD
    done
else
    echo -e "${GREEN}[✓] Başarıyla yakalanan üst blok yüksekliği (CHAIN_HEAD): ${YELLOW}$CHAIN_HEAD${NC}"
fi

# Disk Alanı Kontrolü (export işlemi geçici olarak ek alan gerektirir)
if [ -d "$HOME/.0gchaind/0g-home/geth-home" ]; then
    GETH_HOME_SIZE_KB=$(du -sk "$HOME/.0gchaind/0g-home/geth-home" 2>/dev/null | cut -f1)
    AVAILABLE_KB=$(df --output=avail "$HOME" | tail -1 | tr -d ' ')
    REQUIRED_KB=$((GETH_HOME_SIZE_KB + (GETH_HOME_SIZE_KB / 2)))
    if [ -n "$GETH_HOME_SIZE_KB" ] && [ "$AVAILABLE_KB" -lt "$REQUIRED_KB" ]; then
        echo -e "${YELLOW}[!] UYARI: Disk alanı yetersiz olabilir. Gerekli tahmini: ~$((REQUIRED_KB/1024/1024))GB, Mevcut: ~$((AVAILABLE_KB/1024/1024))GB${NC}"
        read -p "Yine de devam etmek istiyor musunuz? (e/h): " CONTINUE_ANS
        [ "$CONTINUE_ANS" != "e" ] && fail "Kullanıcı tarafından durduruldu (disk alanı uyarısı)."
    fi
fi

# 2. ADIM: Servisleri Durdur ve CL Yedekle
echo -e "${BLUE}[2/8] Mevcut servisler durduruluyor ve CL yedekleniyor...${NC}"
sudo systemctl stop 0gchaind geth 2>/dev/null
BACKUP_DIR="$HOME/.0gchaind/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
cp -r $HOME/.0gchaind/0g-home/0gchaind-home $BACKUP_DIR/0gchaind-home || fail "CL yedeklemesi başarısız oldu, işlem durduruldu."
echo -e "${GREEN}[✓] CL verileri güvenli bölgeye yedeklendi: ${YELLOW}$BACKUP_DIR${NC}"

# 3. ADIM: Bağımlılık Paketleri ve Aristotle v1.0.6 Kurulumu
echo -e "${BLUE}[3/8] Aristotle v1.0.6 indiriliyor...${NC}"

cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
[ -s aristotle.tar.gz ] || fail "Aristotle v1.0.6 indirilemedi (dosya boş veya yok)."

# Arşivin içindeki gerçek klasör adını dinamik olarak yakala (büyük/küçük harf uyuşmazlığı riskini ortadan kaldırır)
EXTRACTED_DIR=$(tar -tzf aristotle.tar.gz | head -1 | cut -f1 -d"/")
[ -n "$EXTRACTED_DIR" ] || fail "Arşiv içeriği okunamadı."

tar -xzf aristotle.tar.gz -C $HOME || fail "Arşiv açılamadı."
rm -f aristotle.tar.gz

rm -rf $HOME/aristotle-used 2>/dev/null
mv "$HOME/$EXTRACTED_DIR" "$HOME/aristotle-used" || fail "Çıkarılan klasör '$EXTRACTED_DIR' bulunamadı/taşınamadı."

[ -f "$HOME/aristotle-used/bin/reth" ] && [ -f "$HOME/aristotle-used/bin/0gchaind" ] || fail "reth veya 0gchaind binary'leri paket içinde bulunamadı."

sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind

mkdir -p $HOME/.0gchaind/0g-home/reth-home
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/
echo -e "${GREEN}[✓] Yeni mimarinin binary ve temel dosyaları hazır (klasör: $EXTRACTED_DIR).${NC}"

# 4. ADIM: Geth Verilerini Dışa Aktarma (export başarısı doğrulanmadan eski veri SİLİNMEZ)
echo -e "${BLUE}[4/8] Geth veritabanından RLP blok ihracı başladı (Bu işlem zaman alacaktır)...${NC}"
EXPORT_FILE="$HOME/.0gchaind/0g-home/chain-export.rlp"

if $HOME/go/bin/geth export \
  --datadir $HOME/.0gchaind/0g-home/geth-home \
  "$EXPORT_FILE" \
  1 $CHAIN_HEAD; then
    if [ -s "$EXPORT_FILE" ]; then
        echo -e "${GREEN}[✓] Export başarılı (boyut: $(du -h "$EXPORT_FILE" | cut -f1)). geth-home siliniyor...${NC}"
        rm -rf $HOME/.0gchaind/0g-home/geth-home
    else
        fail "Export dosyası oluşturulamadı ya da boş. geth-home korundu, işlem durduruldu."
    fi
else
    fail "geth export komutu başarısız oldu. geth-home korundu, işlem durduruldu."
fi
echo -e "${GREEN}[✓] Geth verileri dışarı aktarıldı ve eski veri dizini temizlendi.${NC}"

# 5. ADIM: Reth Init
# NOT: "geth export ... 1 $CHAIN_HEAD" zaten 1. bloktan (genesis hariç) başladığı için
# ayrıca bir "trim/filtreleme" adımına gerek yok — export dosyası doğrudan import edilebilir.
echo -e "${BLUE}[5/8] Reth veritabanı ilklendiriliyor...${NC}"
$HOME/go/bin/reth init \
  --chain $HOME/aristotle-used/geth-genesis.json \
  --datadir $HOME/.0gchaind/0g-home/reth-home || fail "reth init başarısız oldu."
echo -e "${GREEN}[✓] Reth veritabanı ilklendirildi.${NC}"

# 6. ADIM: Otomatik Screen Açma ve Canlı İthalat (Reth Import) — başarı/hata durumu ayrıca kontrol edilir
echo -e "${BLUE}[6/8] 'Corenode_Reth_Import' adında yeni bir Screen açılıyor...${NC}"
echo -e "${YELLOW}[!] Süreç bu aşamada kilitlenecek ve ithalatın bitmesini bekleyecektir.${NC}"
echo -e "${CYAN}[>] İthalat durumunu canlı izlemek için yeni terminalden şu komutu girebilirsin:${NC}"
echo -e "${CYAN}    screen -r Corenode_Reth_Import${NC}"

STATUS_FILE="/tmp/corenode_reth_import_status_$$"
rm -f "$STATUS_FILE"

screen -dmS Corenode_Reth_Import bash -c "$HOME/go/bin/reth import --chain $HOME/aristotle-used/geth-genesis.json --datadir $HOME/.0gchaind/0g-home/reth-home '$EXPORT_FILE'; echo \$? > $STATUS_FILE; exec bash"

# exec bash screen'i canlı tuttuğu için "screen kapandı mı" yerine "durum dosyası oluştu mu" kontrol ediyoruz
while [ ! -f "$STATUS_FILE" ]; do
    sleep 5
done
IMPORT_STATUS=$(cat "$STATUS_FILE")
rm -f "$STATUS_FILE"

if [ "$IMPORT_STATUS" != "0" ]; then
    fail "reth import başarısız oldu (exit code: $IMPORT_STATUS). Detaylar için: screen -r Corenode_Reth_Import"
fi
echo -e "${GREEN}[✓] Reth veri ithalatı (Import) başarıyla bitti! Ana akışa geri dönüldü.${NC}"

# 7. ADIM: Konfigürasyon ve Servis Dosyalarının Yenilenmesi
echo -e "${BLUE}[7/8] Konfigürasyonlar ve systemd servisleri güncelleniyor...${NC}"

CONFIG_FILE="$HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml"
if grep -q "^rpc-dial-url" "$CONFIG_FILE" 2>/dev/null; then
    sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" "$CONFIG_FILE"
else
    echo -e "${YELLOW}[!] UYARI: '$CONFIG_FILE' içinde 'rpc-dial-url' satırı bulunamadı, manuel kontrol et.${NC}"
fi

# Reth Servis Dosyası (tek '\' ile satır devamı)
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
  --nat extip:$(curl -s http://ipv4.icanhazip.com)
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SEVEOF

# 0gchaind Servis Dosyası (tek '\' ile satır devamı)
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
  --chaincfg.node-api.enabled \
  --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \
  --pruning=nothing \
  --chaincfg.restaking.enabled \
  --chaincfg.restaking.symbiotic-rpc-dial-url $ETH_RPC_URL \
  --chaincfg.restaking.symbiotic-get-logs-block-range 1 \
  --home=$HOME/.0gchaind/0g-home/0gchaind-home \
  --p2p.external_address=$(curl -s http://ipv4.icanhazip.com):${OG_PORT}656
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SEVEOF

sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
echo -e "${GREEN}[✓] Yeni servis konfigürasyonları başarıyla sisteme işlendi.${NC}"

# 8. ADIM: Yeni Yapıyı Ayağa Kaldırma ve Doğrulama
echo -e "${BLUE}[8/8] Yeni Reth ve Consensus servisleri tetikleniyor...${NC}"
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
echo -e "   [✓] MIGRATION TAMAMLANDI! NODE BAŞARIYLA RETH MIMARISINE GECTI. [✓]  "
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
