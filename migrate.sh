#!/bin/bash

# Renk Tanımlamaları
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
CYAN='\033[0;36m'
NC='\033[0m' # No Color

# Ekranı Temizle ve Corenode Logosunu Bas
clear
echo -e "${CYAN}"
echo "========================================================================"
echo "   ______   ______   .______       _______ .__   __.   ______   _______   "
echo "  /      | /  __  \\  |   _  \\     |   ____||  \\ |  |  /  __  \\ |       \\  "
echo " |  ,----'|  |  |  | |  |_)  |    |  |__   |   \\|  | |  |  |  ||  .--.  | "
echo " |  |     |  |  |  | |      /     |   __|  |  . \`  | |  |  |  ||  |  |  | "
echo " |  \`----.|  \`--'  | |  |\\  \\----.|  |____ |  |\\   | |  \`--'  ||  '--'  | "
echo "  \\______| \\______/  | _| \`._____||_______||__| \\__|  \\______/ |_______/  "
echo "                                                                        "
echo "               FULLY INTERACTIVE GETH --> RETH MIGRATION                "
echo "========================================================================"
echo -e "${NC}"

# Profil Yükleme
[ -f $HOME/.bash_profile ] && source $HOME/.bash_profile

echo -e "${BLUE}[>] Yapılandırma Ayarları Kontrol Ediliyor...${NC}"
echo "--------------------------------------------------"

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

if [ -z "$CHAIN_HEAD" ] || [ "$CHAIN_HEAD" -eq 0 ]; then
    echo -e "${YELLOW}[!] UYARI: Canlı node RPC portundan veri alınamadı.${NC}"
    read -p "Lütfen ihraç edilecek son blok numarasını manuel girin: " CHAIN_HEAD
    while [ -z "$CHAIN_HEAD" ]; do
        read -p "Blok numarası boş bırakılamaz: " CHAIN_HEAD
    done
else
    echo -e "${GREEN}[✓] Başarıyla yakalanan üst blok yüksekliği (CHAIN_HEAD): ${YELLOW}$CHAIN_HEAD${NC}"
fi

# 2. ADIM: Servisleri Durdur ve CL Yedekle
echo -e "${BLUE}[2/8] Mevcut servisler durduruluyor ve CL yedekleniyor...${NC}"
sudo systemctl stop 0gchaind geth 2>/dev/null
BACKUP_DIR="$HOME/.0gchaind/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
cp -r $HOME/.0gchaind/0g-home/0gchaind-home $BACKUP_DIR/0gchaind-home
echo -e "${GREEN}[✓] CL verileri güvenli bölgeye yedeklendi: ${YELLOW}$BACKUP_DIR${NC}"

# 3. ADIM: Bağımlılık Paketleri ve Aristotle v1.0.6 Kurulumu
echo -e "${BLUE}[3/8] Gerekli paketler kuruluyor ve Aristotle v1.0.6 indiriliyor...${NC}"
sudo apt install screen jq -y &>/dev/null

cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz &>/dev/null
tar -xzvf aristotle.tar.gz -C $HOME &>/dev/null
rm -rf aristotle.tar.gz
rm -rf $HOME/aristotle-used 2>/dev/null
mv $HOME/Aristotle-v1.0.6 $HOME/aristotle-used

sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind

mkdir -p $HOME/.0gchaind/0g-home/reth-home
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/
echo -e "${GREEN}[✓] Yeni mimarinin binary ve temel dosyaları hazır.${NC}"

# 4. ADIM: Geth Verilerini Dinamik Olarak İhraç Etme
echo -e "${BLUE}[4/8] Geth veritabanından RLP blok ihracı başladı (Bu işlem zaman alacaktır)...${NC}"
$HOME/go/bin/geth export \
  --datadir $HOME/.0gchaind/0g-home/geth-home \
  $HOME/.0gchaind/0g-home/chain-export.rlp \
  1 $CHAIN_HEAD

rm -rf $HOME/.0gchaind/0g-home/geth-home
echo -e "${GREEN}[✓] Geth verileri dışarı aktarıldı ve eski veri dizini temizlendi.${NC}"

# 5. ADIM: Reth Init ve Trim Yapılandırması
echo -e "${BLUE}[5/8] Reth veritabanı ilklendiriliyor ve RLP dosyası filtreleniyor...${NC}"
reth init \
  --chain $HOME/aristotle-used/geth-genesis.json \
  --datadir $HOME/.0gchaind/0g-home/reth-home

# Python Trim Scriptini Dinamik Basma
cat << 'PYEOF' > $HOME/.0gchaind/0g-home/trim_export.py
import sys
input_file = "$HOME/.0gchaind/0g-home/chain-export.rlp".replace("$HOME", sys.argv[2])
output_file = "$HOME/.0gchaind/0g-home/chain-export-from-1.rlp".replace("$HOME", sys.argv[2])
start_block = int(sys.argv[1])

with open(input_file, "rb") as fin, open(output_file, "wb") as fout:
    def read_rlp_length(f):
        first = f.read(1)
        if not first: return None, 0
        b = first[0]
        if b < 0xc0: return None, 0
        elif b <= 0xf7: return first, b - 0xc0
        else:
            c = b - 0xf7
            return first + f.read(c), int.from_bytes(f.read(c), 'big')
    while True:
        h, l = read_rlp_length(fin)
        if h is None: break
        body = fin.read(l)
        fout.write(h + body)
PYEOF

python3 $HOME/.0gchaind/0g-home/trim_export.py 1 "$HOME"
echo -e "${GREEN}[✓] Genesis çakışma filtrelemesi başarıyla tamamlandı.${NC}"

# 6. ADIM: Otomatik Screen Açma ve Canlı İthalat (Reth Import)
echo -e "${BLUE}[6/8] 'Corenode_Reth_Import' adında yeni bir Screen açılıyor...${NC}"
echo -e "${YELLOW}[!] Süreç bu aşamada kilitlenecek ve ithalatın bitmesini bekleyecektir.${NC}"
echo -e "${CYAN}[>] İthalat durumunu canlı izlemek için yeni terminalden şu komutu girebilirsin:${NC}"
echo -e "${CYAN}    screen -r Corenode_Reth_Import${NC}"

# Arka planda yeni screen açıp komutu orada canlı/bloklayıcı olarak yürütüyoruz
screen -dmS Corenode_Reth_Import bash -c "$HOME/go/bin/reth import --chain $HOME/aristotle-used/geth-genesis.json --datadir $HOME/.0gchaind/0g-home/reth-home $HOME/.0gchaind/0g-home/chain-export-from-1.rlp; exec bash"

# Screen oturumu canlı olduğu sürece ana scriptin beklemesini tetikliyoruz
while screen -list | grep -q "Corenode_Reth_Import"; do
    sleep 5
done

echo -e "${GREEN}[✓] Reth veri ithalatı (Import) başarıyla bitti! Ana akışa geri dönüldü.${NC}"

# 7. ADIM: Konfigürasyon ve Servis Dosyalarının Yenilenmesi (sed ve sudo tee)
echo -e "${BLUE}[7/8] Konfigürasyonlar ve systemd servisleri güncelleniyor...${NC}"
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml

# Reth Servis Dosyası
sudo tee /etc/systemd/system/reth.service > /dev/null <<SEVEOF
[Unit]
Description=0G Labs Reth Execution Client
After=network.target

[Service]
User=$USER
Type=simple
WorkingDirectory=$HOME/aristotle-used
ExecStart=$HOME/go/bin/reth node \\
  --chain $HOME/aristotle-used/geth-genesis.json \\
  --http \\
  --http.addr 0.0.0.0 \\
  --http.port ${OG_PORT}545 \\
  --http.api eth,net,admin \\
  --authrpc.addr 0.0.0.0 \\
  --authrpc.port ${OG_PORT}551 \\
  --authrpc.jwtsecret $HOME/.0gchaind/0g-home/jwt.hex \\
  --datadir $HOME/.0gchaind/0g-home/reth-home \\
  --ipcpath $HOME/.0gchaind/0g-home/reth-home/eth-engine.ipc \\
  --engine.persistence-threshold 0 \\
  --engine.memory-block-buffer-target 0 \\
  --bootnodes="enode://2bf74c837a98c94ad0fa8f5c58a428237d2040f9269fe622c3dbe4fef68141c28e2097d7af6ebaa041194257543dc112514238361a6498f9a38f70fd56493f96@8.221.140.134:30303" \\
  --port ${OG_PORT}303 \\
  --nat extip:\$(curl -s http://ipv4.icanhazip.com)
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SEVEOF

# 0gchaind Servis Dosyası
sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<SEVEOF
[Unit]
Description=0GChainD Service
After=network.target

[Service]
User=$USER
WorkingDirectory=$HOME/aristotle-used
ExecStart=$HOME/go/bin/0gchaind start \\
  --rpc.laddr tcp://0.0.0.0:${OG_PORT}657 \\
  --chaincfg.chain-spec mainnet \\
  --chaincfg.kzg.trusted-setup-path=$HOME/.0gchaind/0g-home/kzg-trusted-setup.json \\
  --chaincfg.engine.jwt-secret-path=$HOME/.0gchaind/0g-home/jwt.hex \\
  --chaincfg.block-store-service.enabled \\
  --chaincfg.node-api.enabled \\
  --chaincfg.node-api.address 0.0.0.0:${OG_PORT}500 \\
  --chaincfg.engine.rpc-dial-url=http://localhost:${OG_PORT}551 \\
  --pruning=nothing \\
  --chaincfg.restaking.enabled \\
  --chaincfg.restaking.symbiotic-rpc-dial-url $ETH_RPC_URL \\
  --chaincfg.restaking.symbiotic-get-logs-block-range 1 \\
  --home=$HOME/.0gchaind/0g-home/0gchaind-home \\
  --p2p.external_address=\$(curl -s http://ipv4.icanhazip.com):${OG_PORT}656
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
SEVEOF

sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
echo -e "${GREEN}[✓] Yeni servis konfigürasyonları başarıyla sisteme işlendi.${NC}"

# 8. ADIM: Yeni Yapıyı Ayağa Kaldırma ve Kapanış
echo -e "${BLUE}[8/8] Yeni Reth ve Consensus servisleri tetikleniyor...${NC}"
sudo systemctl start reth
sleep 3
sudo systemctl start 0gchaind

echo -e "${GREEN}========================================================================"
echo -e "   [✓] MIGRATION TAMAMLANDI! NODE BAŞARIYLA RETH MIMARISINE GECTI. [✓]  "
echo -e "========================================================================${NC}"
echo -e "${YELLOW}Logları anlık izlemek için aşağıdaki komutları kullanabilirsin:${NC}"
echo -e "    Reth Logları:      ${CYAN}sudo journalctl -u reth -f -o cat${NC}"
echo -e "    Consensus Logları: ${CYAN}sudo journalctl -u 0gchaind -f -o cat${NC}"
echo ""
