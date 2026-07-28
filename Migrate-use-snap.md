# 🔄 Corenode Altyapısı: Geth'den Reth'e Snapshot ile Geçiş Rehberi

Bu rehber, mevcut RLP export/trim/import akışı yerine hazır bir **reth-home snapshot'ı** kullanarak execution katmanını Reth'e taşır.

> 💡 **Tasarım kararı:** Geth→Reth geçişinde değişen tek şey execution (yürütme) katmanıdır. Consensus katmanı (`0gchaind-home`, validator state dahil) **hiç değişmez**. Bu yüzden snapshot'ı yalnızca `reth-home` için indiriyoruz; cosmos/consensus verisine dokunmuyoruz. Böylece `priv_validator_state.json` ile ilgili çifte imzalama riskini baştan tamamen ortadan kaldırmış oluyoruz — ayrı bir yedekleme/geri yükleme adımına bile gerek kalmıyor.

---

## 1️⃣ Servisleri Durdurma ve Güvenlik Yedeği

### Servisleri durdur

```bash
sudo systemctl stop 0gchaind geth
```

### Yedek klasörü oluştur (ihtiyat amaçlı — consensus verisine dokunmuyoruz ama yine de yedekleyelim)

```bash
BACKUP_DIR="$HOME/.0gchaind/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
cp -r $HOME/.0gchaind/0g-home/0gchaind-home $BACKUP_DIR/0gchaind-home
```

> Not: `geth-home` için ayrıca yedek almıyoruz çünkü geth'i tamamen bırakıyoruz ve reth-home snapshot'tan geliyor. İstersen `geth-home`'u da silmeden önce başka bir diske taşıyabilirsin — zorunlu değil ama geri dönüş şansı verir.

---

## 2️⃣ Snapshot'ı Silmeden Önce Doğrula (KRİTİK SIRA)

> ⚠️ **Önemli:** Eski veriyi silmeden önce snapshot'ın gerçekten erişilebilir olduğunu teyit et. Aksi halde sunucu geçici olarak erişilemez durumdaysa elinde ne eski ne yeni veri kalır.

```bash
SNAPSHOT_URL="https://files.corenodehq.xyz/0g/snapshot/"

SNAPSHOT_LISTING=$(curl -sf "$SNAPSHOT_URL") || { echo "HATA: Snapshot sunucusuna erişilemedi."; exit 1; }

LATEST_RETH=$(echo "$SNAPSHOT_LISTING" | grep -oP '0g_\d{8}-\d{4}_\d+_reth\.tar\.lz4' | sort | tail -n 1)

if [ -z "$LATEST_RETH" ]; then
    echo "HATA: Geçerli reth snapshot dosyası bulunamadı, işlem durduruldu."
    exit 1
fi

echo "Bulunan Reth Snapshot: $LATEST_RETH"
```

---

## 3️⃣ Aristotle v1.0.6 Paketi ve Klasör Düzeni

```bash
cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
[ -s aristotle.tar.gz ] || { echo "HATA: indirme başarısız."; exit 1; }
```

### Klasör adını dinamik olarak yakala (paket içindeki gerçek adla eşleşmeyebilir, büyük/küçük harf farkına dikkat)

```bash
EXTRACTED_DIR=$(tar -tzf aristotle.tar.gz | head -1 | cut -f1 -d"/")
tar -xzvf aristotle.tar.gz -C $HOME
rm -rf aristotle.tar.gz
rm -rf $HOME/aristotle-used 2>/dev/null
mv "$HOME/$EXTRACTED_DIR" "$HOME/aristotle-used"
```

### Binary yetkilerini verip go/bin altına taşı

```bash
sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind
```

### Gerekli JWT ve KZG dosyalarını kopyala

```bash
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/
```

---

## 4️⃣ Eski Geth Verisini Temizleme ve Reth Snapshot'ını Kurma

> Bu adıma geldiysen 2. adımda snapshot'ın var olduğunu zaten doğruladın — artık eski veriyi silmek güvenli.

```bash
rm -rf $HOME/.0gchaind/0g-home/geth-home
mkdir -p $HOME/.0gchaind/0g-home/reth-home
```

### Snapshot'ı indir (bütünlük kontrolüyle)

```bash
RETH_URL="${SNAPSHOT_URL}${LATEST_RETH}"

aria2c -x 16 -s 16 -k 1M --continue=true --dir=/tmp --out="$LATEST_RETH" "$RETH_URL"
[ -s "/tmp/$LATEST_RETH" ] || { echo "HATA: Snapshot dosyası boş/yok."; exit 1; }
```

### Arşivi aç

```bash
lz4 -dc "/tmp/$LATEST_RETH" | tar -xf - -C $HOME/.0gchaind/0g-home/reth-home
rm -f "/tmp/$LATEST_RETH"
```

> Not: Snapshot genelde zaten genesis uygulanmış tam bir `reth-home` (db + static_files) içerir. Bu durumda ayrıca `reth init` çalıştırmana gerek yoktur. Eğer snapshot sağlayıcısı "sadece db, genesis hariç" diye belirtiyorsa, açma işleminden önce şu adımı ekle:
> ```bash
> reth init --chain $HOME/aristotle-used/geth-genesis.json --datadir $HOME/.0gchaind/0g-home/reth-home
> ```

---

## 5️⃣ Konfigürasyon Güncellemesi ve Servis Dosyaları

### app.toml engine bağlantısını güncelle

```bash
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" \
  $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
```

### Eski geth servisini temizle

```bash
sudo systemctl disable geth
sudo rm -f /etc/systemd/system/geth.service
```

### Kamu IP'sini önceden çözümle (nat extip'in literal `$(...)` olarak kalmasını önlemek için)

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

> `${PUBLIC_IP}` burada kaçışsız kullanıldı, çünkü değeri az önce çözümledik ve dosyaya gerçek IP olarak gömülmesini istiyoruz (`\$(curl...)` gibi literal/çözümlenmemiş bırakmıyoruz).

### 0gchaind.service dosyasını oluştur (consensus tarafı değişmedi — mevcut haliyle aynı)

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

## 6️⃣ Yeni Servisleri Devreye Alma

```bash
sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
```

### Önce Reth katmanını başlat

```bash
sudo systemctl start reth
```

### Engine API portunun dinlemede olduğunu teyit et

```bash
ss -tlnp | grep ${OG_PORT}551
```

### Reth'in snapshot yüksekliğinden itibaren senkron olduğunu / consensus tip'ine yakınsadığını kontrol et

```bash
curl -s -X POST http://localhost:${OG_PORT}545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' | jq -r '.result'
```

> Snapshot birkaç saat/gün eski olabilir — reth başladığında consensus'tan (0gchaind) gelen engine API çağrılarıyla (`newPayload`/`forkchoiceUpdated`) kalan bloklara otomatik yetişir. Bu senkron tamamlanmadan servisleri "sorunlu" sanıp durdurma; loglardan ilerlemeyi izle.

### Doğrulama tamamsa Consensus katmanını başlat

```bash
sudo systemctl start 0gchaind
```

---

## 📊 Canlı Log Takibi

```bash
sudo journalctl -u reth -f -o cat
sudo journalctl -u 0gchaind -f -o cat
```

---

## Özet: Bu yaklaşımın eski RLP export/trim/import yöntemine göre farkları

| | RLP Export/Import | Snapshot (bu rehber) |
|---|---|---|
| Süre | Saatler (export+import) | Dakikalar (indirme hızına bağlı) |
| Consensus verisine dokunma | Yok (sadece yedekleniyor) | Yok (sadece yedekleniyor) |
| Validator state riski | Yok | Yok (çünkü cosmos snapshot'ı kullanılmıyor) |
| Bağımlılık | `geth`, `python3` (trim script) | `aria2c`, `lz4`, güvenilir bir snapshot kaynağı |
| Snapshot güncelliği | Anlık (kendi node'undan) | Snapshot sağlayıcısına bağlı (biraz gecikmeli olabilir, reth otomatik yetişir) |
