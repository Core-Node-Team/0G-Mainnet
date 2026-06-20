### 🔄 Corenode Altyapısı: Canlı Düğümden Geth'den Reth'e Geçiş (Migration) Rehberi
Bu döküman, sunucunuzda halihazırda çalışan ve altyapı standartlarımıza göre kurulu olan 0gchaind ve geth servislerini koruyarak yürütme katmanını Reth katmanına taşır.

### 1️⃣ Canlı Node Üzerinden Son Blok Yüksekliğini Alma
Node'u durdurmadan önce, bizim yerel RPC portumuz üzerinden (Profilinizdeki $OG_PORT değişkenini kullanarak) geth'in işlediği en son blok numarasını canlı olarak çekiyoruz ve ekrana yazdırıyoruz:


### Ekrana basılan hex tabanlı blok numarasını decimal'e (normal sayıya) çevirip not edin (Örn: 39048765)
```
export CHAIN_HEAD=$(curl -s -X POST http://localhost:${OG_PORT}545 \
  -H "Content-Type: application/json" \
  -d '{"jsonrpc":"2.0","method":"eth_blockNumber","params":[],"id":1}' \
  | jq -r '.result' | xargs printf "%d\n")
```
```
echo "Yakalanan Son Blok Yüksekliği (CHAIN_HEAD): $CHAIN_HEAD"
```
### 2️⃣ Servisleri Durdurma ve Güvenlik Yedeği
Blok numarasını aldıktan sonra, veri tutarlılığı için servisleri durduruyoruz ve sadece Consensus (CL) verilerimizi yedekliyoruz:

```
sudo systemctl stop 0gchaind geth
```
### Yedek klasörü oluşturma
```
BACKUP_DIR="$HOME/.0gchaind/backup-$(date +%Y%m%d-%H%M%S)"
mkdir -p $BACKUP_DIR
```
### Sadece Consensus verisini yedekliyoruz (Reth geçişinde bu veri aynen korunacak)
```
cp -r $HOME/.0gchaind/0g-home/0gchaind-home $BACKUP_DIR/0gchaind-home
```
### 3️⃣ Aristotle v1.0.6 Paketi ve Klasör Düzeni
Yeni sürüm dosyalarını çekip, altyapımızın kullandığı klasör isimlerine göre yerleştiriyoruz:

```
cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
tar -xzvf aristotle.tar.gz -C $HOME
rm -rf aristotle.tar.gz
```
### Klasör ismini Corenode standardımıza (aristotle-used) çeviriyoruz
```
mv $HOME/Aristotle-v1.0.6 $HOME/aristotle-used
```
### Binary yetkilerini verip go/bin altına taşıyoruz
```
sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind
```
### Yeni reth veritabanı klasörünü açıyoruz
```
mkdir -p $HOME/.0gchaind/0g-home/reth-home
```
### Gerekli JWT ve KZG dosyalarını standart 0g-home dizinine kopyalıyoruz
```
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/
```
### 4️⃣ Geth Verilerini İhraç Etme (Export RLP)
Eski geth dizinindeki verileri dışarı aktarıyoruz. <chain_head> yazan yere 1. Adımda not ettiğiniz canlı blok numarasını yazın:


### Bu işlem disk hızına bağlı olarak uzun süreceği için tmux/screen oturumunda çalıştırın!
```
$HOME/go/bin/geth export \
  --datadir $HOME/.0gchaind/0g-home/geth-home \
  $HOME/.0gchaind/0g-home/chain-export.rlp \
  1 $CHAIN_HEAD
```
### 5️⃣ Reth İlklendirme ve RLP Filtreleme (Trim)
Reth mimarisini genesis dosyası ile ilklendirip, ihraç edilen veri bloğundaki çakışma yaratacak 0. (genesis) bloğu ayıklıyoruz:


### Reth Init
```
reth init \
  --chain $HOME/aristotle-used/geth-genesis.json \
  --datadir $HOME/.0gchaind/0g-home/reth-home
```
### Trim scriptini sudo tee ile oluşturuyoruz
```
sudo tee $HOME/.0gchaind/0g-home/trim_export.py > /dev/null <<EOF
import sys

input_file = "$HOME/.0gchaind/0g-home/chain-export.rlp"
output_file = "$HOME/.0gchaind/0g-home/chain-export-from-{start}.rlp"

start_block = int(sys.argv[1]) if len(sys.argv) > 1 else 1
output_file = output_file.format(start=start_block)

print(f"Trimming blocks before {start_block}, output: {output_file}")

def read_rlp_length(f):
    first = f.read(1)
    if not first:
        return None, 0
    b = first[0]
    if b < 0xc0:
        return None, 0
    elif b <= 0xf7:
        return first, b - 0xc0
    else:
        len_bytes_count = b - 0xf7
        len_bytes = f.read(len_bytes_count)
        return first + len_bytes, int.from_bytes(len_bytes, 'big')

def get_block_number(block_data):
    offset = 0
    b = block_data[offset]
    offset += 1 if b <= 0xf7 else 1 + (b - 0xf7)
    b = block_data[offset]
    offset += 1 if b <= 0xf7 else 1 + (b - 0xf7)
    for _ in range(8):
        b = block_data[offset]
        if b <= 0x80:
            offset += 1
        elif b <= 0xb7:
            offset += 1 + (b - 0x80)
        elif b <= 0xbf:
            n = b - 0xb7
            offset += 1 + n + int.from_bytes(block_data[offset+1:offset+1+n], 'big')
        elif b <= 0xf7:
            offset += 1 + (b - 0xc0)
        else:
            n = b - 0xf7
            offset += 1 + n + int.from_bytes(block_data[offset+1:offset+1+n], 'big')
    b = block_data[offset]
    if b == 0x80: return 0
    if b < 0x80: return b
    length = b - 0x80
    return int.from_bytes(block_data[offset+1:offset+1+length], 'big')

block_count = 0
skipped = 0

with open(input_file, "rb") as fin, open(output_file, "wb") as fout:
    while True:
        header_bytes, length = read_rlp_length(fin)
        if header_bytes is None:
            break
        block_body = fin.read(length)
        if len(block_body) < length:
            break
        full_block = header_bytes + block_body
        try:
            block_number = get_block_number(full_block)
        except Exception as e:
            print(f"Warning: could not parse block at index {block_count + skipped}, writing anyway: {e}")
            fout.write(full_block)
            block_count += 1
            continue
        if block_number < start_block:
            skipped += 1
            if skipped % 100000 == 0:
                print(f"Skipped {skipped} blocks (current: {block_number})...")
        else:
            fout.write(full_block)
            block_count += 1
            if block_count % 100000 == 0:
                print(f"Written {block_count} blocks (current: {block_number})...")

print(f"Done. Skipped {skipped}, wrote {block_count} blocks to {output_file}")
EOF
```
### Ayıklama işlemini başlatıyoruz
```
python3 $HOME/.0gchaind/0g-home/trim_export.py 1
```
### 6️⃣ Blok Verilerini Reth İçine İthal Etme (Import)
Temizlenen RLP dosyasını arka planda Reth üzerine yazdırıyoruz:

```
nohup $HOME/go/bin/reth import \
  --chain $HOME/aristotle-used/geth-genesis.json \
  --datadir $HOME/.0gchaind/0g-home/reth-home \
  $HOME/.0gchaind/0g-home/chain-export-from-1.rlp \
  >> $HOME/.0gchaind/0g-home/reth-import.log 2>&1 &
```
### İthalat durumunu izlemek için:
```
tail -f $HOME/.0gchaind/0g-home/reth-import.log
```
⚠️ KRİTİK GEÇİŞ KURALI: reth-import.log dosyasındaki işlemler tamamen bitmeden ve reth ağ yüksekliğine ulaşmadan asla bir sonraki adıma geçip servisleri başlatmayın. Aksi takdirde sistem -38002 Invalid forkchoice state hatası verir.

### 7️⃣ Sed ile Konfigürasyon Ayarı ve Yeni Servis Dosyaları
Mevcut app.toml üzerindeki engine bağlantısını yeni port yapımıza göre güncelliyoruz:

```
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
```
Eski servisleri temizleyip, Corenode standartlarına göre yeni reth.service ve güncellenmiş 0gchaind.service dosyalarını yazıyoruz:

```
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
  --nat extip:\$(curl -s http://ipv4.icanhazip.com)
Restart=always
RestartSec=3
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
```
```
Bash
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
  --p2p.external_address=\$(curl -s http://ipv4.icanhazip.com):${OG_PORT}656
Restart=always
RestartSec=5
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF
```
### 8️⃣ Yeni Servisleri Devreye Alma
Import işlemi sorunsuzca bittiyse yeni mimariyi çalıştırıyoruz:

```
sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
```
### Önce Reth katmanını başlatıyoruz
```
sudo systemctl start reth
```
### Engine API portunun (Örn: 59551) dinlemede olduğunu teyit edin
```
ss -tlnp | grep ${OG_PORT}551
```
### Doğrulama tamamsa Consensus katmanını başlatıyoruz
```
sudo systemctl start 0gchaind
```
📊 Canlı Logların Takibi
Yeni sistemin servis loglarını şu komutlarla temizce izleyebilirsiniz:


### Reth izleme
```
sudo journalctl -u reth -f -o cat
```
### 0gchaind izleme
```
sudo journalctl -u 0gchaind -f -o cat
```

### OTO MİGRATE

### 1️⃣ Bağımlılık Kontrolü (İsteğe Bağlı)
Script zaten gerekli paketleri (screen vb.) kendi içinde kuruyor ancak sunucuda curl yüklü değilse scripti GitHub'dan çekebilmek için önce curl paketini sağlama alıyoruz:

```
sudo apt update && sudo apt install curl -y
```
### 2️⃣ Scripti GitHub'dan Çekme ve Yetkilendirme
Hazırladığın ham (raw) linki kullanarak scripti doğrudan $HOME dizinine indiriyor ve Linux üzerinde çalıştırılabilir (executable) hale getiriyoruz:


### Scripti sunucuya indir
```
curl -o $HOME/migrate.sh https://raw.githubusercontent.com/Core-Node-Team/0G-Mainnet/refs/heads/main/migrate.sh
```
### Çalıştırma yetkisi ver
```
chmod +x $HOME/migrate.sh
```
### 3️⃣ Otomasyon Scriptini Başlatma
Sistem değişkenlerinin ($OG_PORT, $ETH_RPC_URL) doğru okunabilmesi için profili tazeleyip scripti tetikliyoruz:
```
source $HOME/.bash_profile
$HOME/migrate.sh
```
⚙️ Script Çalışırken Dikkat Edilmesi Gerekenler:
- Canlı Blok Kontrolü: Script ilk başladığında yerel RPC portun üzerinden güncel bloğu otomatik yakalayıp ekrana basacaktır.

- İthalat Aşaması (Adım 6): Script, Corenode_Reth_Import adında yeni bir Screen oturumu açıp ithalatı orada başlatacak ve işlem bitene kadar ana ekranda bekleyecektir.

- Canlı İthalat Loglarını İzleme: Eğer arka tarafta Reth'in blokları nasıl ithal ettiğini (import sürecini) canlı izlemek istersen, yeni bir terminal sekmesi açarak şu komutla screen oturumuna bağlanabilirsin:

```
screen -r Corenode_Reth_Import
```
- (Screen ekranından ana akışı bozmadan çıkmak için klavyeden sırasıyla Ctrl + A ve ardından D tuşlarına basman yeterlidir).

- İthalat bittiğinde script otomatik olarak uyanacak, konfigürasyonları sed ile güncelleyecek, servis dosyalarını sudo tee ile basıp süreci başarıyla tamamlayacaktır!
