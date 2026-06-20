
### 🛠 Corenode Altyapısı: Sıfırdan Reth & 0GChainD Kurulumu (Aristotle Mainnet)
### 1️⃣ Paket ve Go Kurulumu
Eğer sunucu sıfır ise gerekli bağımlılıkları ve Go ortamını kurarak başlıyoruz:

```
sudo apt update && sudo apt upgrade -y
sudo apt install curl git wget htop tmux build-essential jq make lz4 gcc unzip -y
```
```
cd $HOME
VER="1.23.4"
wget "https://golang.org/dl/go$VER.linux-amd64.tar.gz"
sudo rm -rf /usr/local/go
sudo tar -C /usr/local -xzf "go$VER.linux-amd64.tar.gz"
rm "go$VER.linux-amd64.tar.gz"

[ ! -f ~/.bash_profile ] && touch ~/.bash_profile
echo "export PATH=\$PATH:/usr/local/go/bin:~/go/bin" >> ~/.bash_profile
source ~/.bash_profile
mkdir -p ~/go/bin
```
### 2️⃣ Değişkenleri Tanımlama
Corenode port ve moniker standartlarımızı profile işliyoruz:

```
echo "export OG_MONIKER=\"your-moniker-name\"" >> $HOME/.bash_profile
echo "export OG_PORT=\"59\"" >> $HOME/.bash_profile
echo "export ETH_RPC_URL=\"https://your-ethereum-mainnet-rpc-endpoint\"" >> $HOME/.bash_profile
source $HOME/.bash_profile
```
### 3️⃣ Aristotle v1.0.6 Dosyalarının İndirilmesi ve Dizinlerin Taşınması
Resmi paketi çekip ham dizin yapısını bizim $HOME/.0gchaind mimarimize göre dağıtıyoruz:

```
cd $HOME
wget -O aristotle.tar.gz https://github.com/0gfoundation/0gchain-Aristotle/releases/download/v1.0.6/aristotle-v1.0.6.tar.gz
tar -xzvf aristotle.tar.gz -C $HOME
rm -rf aristotle.tar.gz
```
### Klasör ismini Corenode standardına çeviriyoruz
```
mv $HOME/Aristotle-v1.0.6 $HOME/aristotle-used
```
### İzinleri tanımlama ve binary'leri go/bin altına kopyalama
```
sudo chmod 777 $HOME/aristotle-used/bin/*
cp $HOME/aristotle-used/bin/reth $HOME/go/bin/reth
cp $HOME/aristotle-used/bin/0gchaind $HOME/go/bin/0gchaind
```
### Corenode ana veri dizinlerini oluşturma
```
mkdir -p $HOME/.0gchaind/0g-home/0gchaind-home/config
mkdir -p $HOME/.0gchaind/0g-home/reth-home
```
### Gerekli kzg, genesis ve jwt dosyalarını doğru yerlere taşıma / kopyalama
```
cp $HOME/aristotle-used/0g-home/0gchaind-home/config/genesis.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
cp $HOME/aristotle-used/jwt.hex $HOME/.0gchaind/0g-home/
cp $HOME/aristotle-used/kzg-trusted-setup.json $HOME/.0gchaind/0g-home/
```
### 4️⃣ Node İlklendirme (Initialization)
Her iki katmanı da genesis ve zincir speklerine göre ilklendiriyoruz:

### Consensus Katmanını İlklendirme
```
0gchaind init $OG_MONIKER --home $HOME/.0gchaind/tmp --chaincfg.chain-spec mainnet
```
### Anahtarları ve validator durum dosyalarını kalıcı Corenode dizinine taşıma
```
mv $HOME/.0gchaind/tmp/data/priv_validator_state.json $HOME/.0gchaind/0g-home/0gchaind-home/data/
mv $HOME/.0gchaind/tmp/config/node_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
mv $HOME/.0gchaind/tmp/config/priv_validator_key.json $HOME/.0gchaind/0g-home/0gchaind-home/config/
rm -rf $HOME/.0gchaind/tmp
```
### Execution (Reth) Katmanını İlklendirme
```
reth init \
  --chain $HOME/aristotle-used/geth-genesis.json \
  --datadir $HOME/.0gchaind/0g-home/reth-home
  ```
### 5️⃣ Sed ile Dinamik Port Değişiklikleri ve Yapılandırma
toml dosyalarını bizim OG_PORT (Örn: 59) yapımıza göre otomatik olarak sed ile güncelliyoruz:


### Moniker ismini config.toml dosyasına işleme
```
sed -i "s|^moniker *=.*|moniker = \"${OG_MONIKER}\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
```
### client.toml Port Güncellemesi
```
sed -i "s|node = .*|node = \"tcp://localhost:${OG_PORT}657\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/client.toml
```
### config.toml Port Güncellemeleri (P2P, RPC, Proxy, Prometheus)
```
sed -i "s|laddr = \"tcp://0.0.0.0:26656\"|laddr = \"tcp://0.0.0.0:${OG_PORT}656\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
sed -i "s|laddr = \"tcp://127.0.0.1:26657\"|laddr = \"tcp://127.0.0.1:${OG_PORT}657\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
sed -i "s|^proxy_app = .*|proxy_app = \"tcp://127.0.0.1:${OG_PORT}658\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
sed -i "s|^pprof_laddr = .*|pprof_laddr = \"0.0.0.0:${OG_PORT}060\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
sed -i "s|prometheus_listen_addr = \".*\"|prometheus_listen_addr = \"0.0.0.0:${OG_PORT}660\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
```
### app.toml Port ve Restaking API Güncellemeleri
```
sed -i "s|address = \".*:3500\"|address = \"127.0.0.1:${OG_PORT}500\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
sed -i "s|^rpc-dial-url *=.*|rpc-dial-url = \"http://localhost:${OG_PORT}551\"|" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
```
### Pruning ve Indexer Ayarları (Corenode Standartı)
```
sed -i -e "s/^pruning *=.*/pruning = \"custom\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
sed -i -e "s/^pruning-keep-recent *=.*/pruning-keep-recent = \"100\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
sed -i -e "s/^pruning-interval *=.*/pruning-interval = \"19\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/app.toml
sed -i -e "s/^indexer *=.*/indexer = \"null\"/" $HOME/.0gchaind/0g-home/0gchaind-home/config/config.toml
```
### Client.toml için Symlink Oluşturulması
```
ln -sf $HOME/.0gchaind/0g-home/0gchaind-home/config/client.toml $HOME/.0gchaind/config/client.toml
```
### 6️⃣ Servis Dosyalarının Oluşturulması (sudo tee Kullanımı)
Reth ve 0gchaind servislerini, Corenode dizin yapısına ($HOME/.0gchaind/0g-home/) ve port değişkenlerine uyumlu olarak yazıyoruz:

Reth Servisi (/etc/systemd/system/reth.service):

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
### ⚡ BÖLÜM 5: Servislerin Başlatılması ve Doğrulama
Sıralama kurallarına sadık kalarak servislerimizi tetikliyoruz.


#### Daemon yenileme ve servisleri aktif etme
```
sudo systemctl daemon-reload
sudo systemctl enable reth 0gchaind
```
#### ÖNCE EL (Reth) başlatılır
```
sudo systemctl start reth
```
#### Engine API portunun ayağa kalktığını (8551 alanınız üzerinden) kontrol edin
#### Örneğin OG_PORT=59 ise port 59551 olacaktır.
```
ss -tlnp | grep ${OG_PORT}551
```
#### Engine hazır ise CL (0gchaind) başlatılır
```
sudo systemctl start 0gchaind
```
Log İzleme Kuralları

#### Reth durum takibi
```
sudo journalctl -u reth -f -o cat
```
#### Consensus durum takibi
```
sudo journalctl -u 0gchaind -f -o cat
```
Senkronizasyon Kontrolü
```
local_height=$(curl -s localhost:${OG_PORT}657/status | jq -r .result.sync_info.latest_block_height); network_height=$(curl -s http://rpc.0g.ai/status | jq -r .result.sync_info.latest_block_height); blocks_left=$((network_height - local_height)); echo "Node height: $local_height"; echo "Network height: $network_height"; echo "Remaining blocks: $blocks_left"
```
