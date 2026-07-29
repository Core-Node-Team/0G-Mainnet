# 🔄 Corenode Altyapısı: Geth'den Reth'e Snapshot ile Geçiş Rehberi (Cosmos + Reth)

Bu rehber hem consensus (cosmos) hem de execution (reth) verisini hazır snapshot'lardan kurar. RLP export/trim/import'a göre çok daha hızlıdır, ama consensus verisi de değiştiği için `priv_validator_state.json` (çifte imzalama koruması) adımına özellikle dikkat edilmelidir.

---

## 1️⃣ Port ve RPC Yapılandırması

```bash
if [ -z "$OG_PORT" ]; then
    read -p "Lütfen OG_PORT ön ekini giriniz (Örn: 59): " OG_PORT
    export OG_PORT
    echo "export OG_PORT=\"$OG_PORT\"" >> $HOME/.bash_profile
fi

if [ -z "$ETH_RPC_URL" ]; then
    read -p "Lütfen Ethereum Mainnet RPC URL adresini giriniz: " ETH_RPC_URL
    export ETH_RPC_URL
    echo "export ETH_RPC_URL=\"$ETH_RPC_URL\"" >> $HOME/.bash_profile
fi

source $HOME/.bash_profile
echo "OG_PORT=$OG_PORT / ETH_RPC_URL=$ETH_RPC_URL"
```

> ⚠️ Bu iki değişkeni bir daha bu dokümanın sonuna kadar **elle boşaltmayın** (`ETH_RPC_URL=` gibi tek başına bir atama satırı asla yazmayın) — servis dosyaları bu değerleri en sonda kullanıyor.

---

## 2️⃣ Servisleri Durdurma ve Consensus Yedeği

```bash
sudo systemctl stop 0gchaind geth reth 2>/dev/null

BACKUP_DIR="$HOME/.0gchaind/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
cp -r $HOME/.0gchaind/0g-home/0gchaind-home $BACKUP_DIR/0gchaind-home
```

---

## 3️⃣ Snapshot Kaynağını Doğrula (VERİ SİLİNMEDEN ÖNCE — hem cosmos hem reth)

> ⚠️ **Kritik sıra:** Aşağıdaki doğrulama başarısız olursa hiçbir yerel veri silinmemiş olmalı. Bu yüzden bu adım, verinin silindiği 5. adımdan **önce** gelir ve başarısız olursa script burada durur.

```bash
SNAPSHOT_URL="https://files.corenodehq.xyz/0g/snapshot/"

SNAPSHOT_LISTING=$(curl -sf "$SNAPSHOT_URL") || { echo "HATA: Snapshot sunucusuna erişilemedi."; exit 1; }

LATEST_COSMOS=$(echo "$SNAPSHOT_LISTING" | grep -oP '0g_\d{8}-\d{4}_\d+_cosmos\.tar\.lz4' | sort | tail -n 1)
LATEST_RETH=$(echo "$SNAPSHOT_LISTING" | grep -oP '0g_\d{8}-\d{4}_\d+_reth\.tar\.lz4' | sort | tail -n 1)

if [ -z "$LATEST_COSMOS" ] || [ -z "$LATEST_RETH" ]; then
    echo "HATA: Geçerli cosmos veya reth snapshot dosyası bulunamadı. Hiçbir veri silinmedi."
    exit 1
fi

COSMOS_URL="${SNAPSHOT_URL}${LATEST_COSMOS}"
RETH_URL="${SNAPSHOT_URL}${LATEST_RETH}"

if ! curl -s --head "$COSMOS_URL" | head -n 1 | grep -q "200"; then
    echo "HATA: Cosmos snapshot URL'i erişilemez durumda. Hiçbir veri silinmedi."
    exit 1
fi
if ! curl -s --head "$RETH_URL" | head -n 1 | grep -q "200"; then
    echo "HATA: Reth snapshot URL'i erişilemez durumda. Hiçbir veri silinmedi."
    exit 1
fi

echo "Doğrulandı — Cosmos: $LATEST_COSMOS / Reth: $LATEST_RETH"
```

---

## 4️⃣ Aristotle v1.0.6 Paketi ve Klasör Düzeni

```bash
cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
[ -s aristotle.tar.gz ] || { echo "HATA: indirme başarısız."; exit 1; }
```

### Klasör adını dinamik yakala ve önceki kalıntıyı temizle

```bash
EXTRACTED_DIR=$(tar -tzf aristotle.tar.gz | head -1 | cut -f1 -d"/")
tar -xzvf aristotle.tar.gz -C $HOME
rm -rf aristotle.tar.gz

# ÖNEMLİ: hedef klasör zaten varsa mv onu hedefin İÇİNE taşır, önce temizlemek gerekir
rm -rf $HOME/aristotle-used 2>/dev/null
mv "$HOME/$EXTRACTED_DIR" "$HOME/aristotle-used"
```

### Binary yetkilerini ver ve go/bin altına taşı

```bash
mkdir -p $HOME/go/bin
sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind
```

### Gerekli JWT ve KZG dosyalarını kopyala

```bash
mkdir -p $HOME/.0gchaind/0g-home/reth-home
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/
```

---

## 5️⃣ Eski Verileri Silme (artık snapshot doğrulandığı için güvenle yapılıyor)

### Validator state'i yedekle — KRİTİK, sessizce geçilmez

```bash
PVS_FILE="$HOME/.0gchaind/0g-home/0gchaind-home/data/priv_validator_state.json"
PVS_BACKUP="$HOME/.0gchaind/priv_validator_state.json.backup"

if [ -f "$PVS_FILE" ]; then
    mv "$PVS_FILE" "$PVS_BACKUP" || { echo "HATA: priv_validator_state.json yedeklenemedi! Çifte imzalama riski, işlem durduruldu."; exit 1; }
    PVS_WAS_BACKED_UP=1
    echo "priv_validator_state.json yedeklendi."
else
    PVS_WAS_BACKED_UP=0
    echo "UYARI: priv_validator_state.json bulunamadı (yeni kurulum olabilir)."
fi
```

### Eski geth, cosmos ve reth verilerini sil

```bash
rm -rf $HOME/.0gchaind/0g-home/geth-home
rm -rf $HOME/.0gchaind/0g-home/0gchaind-home/data
rm -rf $HOME/.0gchaind/0g-home/reth-home/db
rm -rf $HOME/.0gchaind/0g-home/reth-home/static_files
```

---

## 6️⃣ Snapshot İndirme ve Açma (Cosmos + Reth)

```bash
mkdir -p $HOME/.0gchaind/0g-home/0gchaind-home
mkdir -p $HOME/.0gchaind/0g-home/reth-home

echo "Cosmos verisi indiriliyor..."
aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_COSMOS" "$COSMOS_URL" \
    || { echo "HATA: Cosmos snapshot indirilemedi."; exit 1; }
[ -s "/tmp/$LATEST_COSMOS" ] || { echo "HATA: Cosmos snapshot dosyası boş/yok."; exit 1; }

lz4 -dc "/tmp/$LATEST_COSMOS" | tar -xf - -C $HOME/.0gchaind/0g-home/0gchaind-home \
    || { echo "HATA: Cosmos snapshot açılamadı."; exit 1; }
rm -f "/tmp/$LATEST_COSMOS"

echo "Reth verisi indiriliyor..."
aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_RETH" "$RETH_URL" \
    || { echo "HATA: Reth snapshot indirilemedi."; exit 1; }
[ -s "/tmp/$LATEST_RETH" ] || { echo "HATA: Reth snapshot dosyası boş/yok."; exit 1; }

lz4 -dc "/tmp/$LATEST_RETH" | tar -xf - -C $HOME/.0gchaind/0g-home/reth-home \
    || { echo "HATA: Reth snapshot açılamadı."; exit 1; }
rm -f "/tmp/$LATEST_RETH"

echo "Snapshot'lar başarıyla açıldı."
```

### Validator state'i geri yükle — KRİTİK, sessizce geçilmez

```bash
mkdir -p "$HOME/.0gchaind/0g-home/0gchaind-home/data"

if [ "$PVS_WAS_BACKED_UP" -eq 1 ]; then
    mv "$PVS_BACKUP" "$PVS_FILE" || { echo "HATA: priv_validator_state.json GERİ YÜKLENEMEDİ! 0gchaind'i başlatma, çifte imzalama riski var. Yedek: $PVS_BACKUP"; exit 1; }
    echo "priv_validator_state.json geri yüklendi (orijinal imzalama geçmişi korundu)."
else
    echo "Geri yüklenecek yedek yoktu, snapshot'ın kendi dosyası kullanılacak."
fi
```

---

## 7️⃣ Konfigürasyon Güncellemesi ve Servis Dosyaları

### app.toml engine bağlantısını güncelle

```bash
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" \
  $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
```

### Eski geth servisini temizle

```bash
sudo systemctl disable geth 2>/dev/null
sudo rm -f /etc/systemd/system/geth.service 2>/dev/null
```

### Kamu IP'sini önceden çözümle

```bash
PUBLIC_IP=$(curl -s http://ipv4.icanhazip.com)
[ -n "$PUBLIC_IP" ] || { echo "HATA: kamu IP alınamadı."; exit 1; }
```

### reth.service dosyasını oluştur

```bash
sudo tee /etc/systemd/system/reth.service > /dev/null <<EOF
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
  --nat extip:${PUBLIC_IP}
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
```

### 0gchaind.service dosyasını oluştur

> `$ETH_RPC_URL` burada 1. adımda ayarladığınız değer olmalı — aradan geçen hiçbir yerde bu değişkeni boşaltmayın.

```bash
sudo tee /etc/systemd/system/0gchaind.service > /dev/null <<EOF
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
  --p2p.external_address=${PUBLIC_IP}:${OG_PORT}656
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
```

---

## 8️⃣ Yeni Servisleri Devreye Alma

```bash
sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
```

### Önce Reth katmanını başlat

```bash
sudo systemctl start reth
sleep 5
sudo systemctl is-active --quiet reth || echo "UYARI: reth başlamadı, loglara bak: sudo journalctl -u reth -n 50 --no-pager"
```

### Engine API portunun dinlemede olduğunu teyit et

```bash
ss -tlnp | grep ${OG_PORT}551
```

### Doğrulama tamamsa Consensus katmanını başlat

```bash
sudo systemctl start 0gchaind
sleep 5
sudo systemctl is-active --quiet 0gchaind || echo "UYARI: 0gchaind başlamadı, loglara bak: sudo journalctl -u 0gchaind -n 50 --no-pager"
```

---

## 📊 Canlı Log Takibi

```bash
sudo journalctl -u reth -f -o cat
sudo journalctl -u 0gchaind -f -o cat
```

---

## Bu sürümde önceki taslağa göre yapılan düzeltmeler

- Doğrulama (hem cosmos hem reth snapshot'ının var ve erişilebilir olduğu) artık **veri silinmeden önce** yapılıyor; başarısızsa `exit 1` ile duruyor.
- Snapshot bulunamazsa / URL erişilemezse script artık sadece mesaj yazıp devam etmiyor, **duruyor**.
- `priv_validator_state.json` yedekleme ve geri yükleme artık `|| true` ile sessizce geçilmiyor — başarısız olursa script durup 0gchaind'i başlatmıyor.
- `aristotle-used` klasörü `mv`'den önce temizleniyor (yanlış iç içe taşınma riski kalkıyor).
- Eski `geth-home` de temizlik adımına eklendi.
- Tek başına duran `ETH_RPC_URL=` gibi değişkeni boşaltan kalıntı satır kaldırıldı; OG_PORT/ETH_RPC_URL artık en başta tek, tutarlı bir bölümde soruluyor.
