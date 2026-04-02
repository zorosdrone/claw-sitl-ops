# OpenClaw向け ArduPilot SITL 接続確認

## 目的

OpenClaw はクラウド上の VPS で動作し、ArduPilot SITL は WSL 上で動作する。このドキュメントでは、Tailscale 経由で VPS 上の OpenClaw から WSL 上の SITL telemetry を受け取れることを確認する。送信先は Tailscale のホスト名で指定する。

このドキュメントで確認する内容は次の 3 点である。

1. WSL 上の SITL が VPS の Tailscale のホスト名へ MAVLink を送信できること
2. VPS 側で heartbeat と flight mode を受信できること
3. OpenClaw 実装に組み込む際の接続形が明確であること

## 前提

- OpenClaw は VPS 上で動作する
- ArduPilot SITL は WSL 上で動作する
- VPS と WSL の両方に Tailscale が導入済みである
- WSL 上で `sim_vehicle.py` が実行できる
- ArduPilot Rover が `~/GitHub/ardupilot/Rover` に存在する

この構成では、最初の検証として VPS から WSL へ直接つなぎに行くより、WSL 上の SITL から VPS へ MAVLink を送信し、VPS 側で待ち受ける方が確実である。

理由は次のとおり。

- WSL2 は NAT 配下なので、外部から WSL 内プロセスへ直接入る経路は切り分けが複雑になる
- SITL は `--out` を追加するだけで、VPS へ telemetry を複製送信できる
- OpenClaw が実際に受け取る経路と同じ形で検証できる

## 構成

最小構成は次のとおり。

- WSL 上の SITL が MAVLink を送信する
- 送信先は VPS の Tailscale のホスト名とする
- VPS 上の OpenClaw は UDP ポートを待ち受ける

接続イメージ:

- WSL 側 SITL: `--out=udp:<VPSのホスト名>:14550`
- VPS 側 OpenClaw: `udpin:0.0.0.0:14550`

このドキュメントでは、OpenClaw 本体の前に MAVProxy または Python スクリプトで同じ待ち受けを行い、疎通確認する。

## 手順

### 1. Tailscale のホスト名を確認する

WSL 側と VPS 側の両方で次を実行する。

```bash
tailscale status
```

以降は次のように仮定する。

- WSL 側ホスト名: `trigkeys5-wsl`
- VPS 側ホスト名: `openclaw`

ここで重要なのは、SITL の送信先には VPS 側の Tailscale のホスト名を使うことだ。

### 2. WSL 側で SITL を起動する

WSL 上で SITL を起動する。OpenClaw 向けの確認では、VPS の Tailscale のホスト名に向けた `--out` を必ず含める。

このリポジトリには、OpenClaw 向けの起動スクリプト [start_sitl4openclaw.sh](../../start_sitl4openclaw.sh) を追加している。通常はこちらを使う。

```bash
./start_sitl4openclaw.sh openclaw
```

または環境変数でも指定できる。

```bash
VPS_TAILSCALE_IP=openclaw ./start_sitl4openclaw.sh
```

既定では、SITL の送信先は VPS 側 UDP `14550` だけである。ローカル Backend にも同時送信したい場合は次を使う。

```bash
ENABLE_LOCAL_BACKEND_OUT=1 ./start_sitl4openclaw.sh openclaw
```

内部では、おおむね次のコマンドを実行している。

```bash
sim_vehicle.py -v Rover \
  --out=udp:openclaw:14550 \
  -l 35.867722,140.263472,10,0
```

ローカルの Backend や別の確認系も併用したい場合は、`--out` を追加で並べればよい。

```bash
sim_vehicle.py -v Rover \
  --out=udp:127.0.0.1:14552 \
  --out=udp:openclaw:14550 \
  -l 35.867722,140.263472,10,0
```

ただし、OpenClaw 向けの疎通確認だけなら、VPS 向けの `--out` だけで十分である。

補足:

- `OPENCLAW_PORT` 環境変数で VPS 側待ち受けポートを変更できる
- `ENABLE_LOCAL_BACKEND_OUT=1` を付けると `udp:127.0.0.1:14552` にも同時送信する

### 3. VPS 側で MAVProxy 受信を確認する

初回のみ、VPS 上へ MAVProxy をグローバルにインストールしておく。以後は activate 不要で `mavproxy.py` を直接使える。

```bash
sudo apt update
sudo apt install -y python3 python3-venv python3-pip
sudo python3 -m pip install --upgrade pip
sudo python3 -m pip install --break-system-packages MAVProxy future
```

`sudo apt update` がタイムアウトする環境では、IPv4 を強制して進める。

```bash
sudo apt -o Acquire::ForceIPv4=true update
sudo apt -o Acquire::ForceIPv4=true install -y python3 python3-venv python3-pip
```

補足:

- `MAVProxy` を入れると依存として `pymavlink` も入る
- 環境によっては `mavproxy.py` 実行時に `ModuleNotFoundError: No module named 'future'` が出ることがある。その場合は同じコマンドに `future` を含めて再実行する
- グローバルに入れたあとは activate は不要で、そのまま `mavproxy.py` を起動する
- インストール確認だけなら `mavproxy.py --help` でよい
- 今回のように `sudo apt -o Acquire::ForceIPv4=true update` で通るなら、原因は IPv6 側の到達性であり、IPv4 の外向き通信は正常である
- 毎回指定したくない場合は `/etc/apt/apt.conf.d/99force-ipv4` に `Acquire::ForceIPv4 "true";` を置くとよい
- `curl -4 -I http://91.189.91.95/ubuntu/` が通るなら、少なくとも Ubuntu ミラーへの IPv4 到達性はある

VPS 上で次を実行する。GUI 環境でない VPS では `--console` は付けない。

```bash
mavproxy.py --master udpin:0.0.0.0:14550
```

確認ポイント:

- `Waiting for heartbeat` のあとに接続が確立する
- プロンプトが `GUIDED>` などのモード名になる
- `status` で `MasterIn` が増える
- `watch HEARTBEAT` で heartbeat が流れる

GUI 環境でコンソールを開きたい場合だけ `--console` を付ける。

ここで mode 名が出て `MasterIn` が増えていれば、VPS は SITL telemetry を受け取れている。

### 4. VPS 側で Python からも確認する

OpenClaw 実装に近い形で確認するには、VPS 上で [sample_receive_heartbeat_vps.py](sample_receive_heartbeat_vps.py) を `python3` で実行する。

```bash
python3 01_APSitl_doc/sample_receive_heartbeat_vps.py
```

待ち受けポートを変えたい場合は `--endpoint` を使う。

```bash
python3 01_APSitl_doc/sample_receive_heartbeat_vps.py \
  --endpoint udpin:0.0.0.0:14550
```

想定結果:

- `wait_heartbeat()` が戻る
- `target_system` と `target_component` が表示される
- `flightmode` が取得できる

この確認が通れば、OpenClaw から同じ待ち受け設定を使える見通しが立つ。

### 5. OpenClaw の接続形に置き換える

VPS 上の OpenClaw が MAVLink を直接受ける構成なら、考え方は次のとおりである。

- WSL 上の SITL が VPS にtelemetry を送る
- OpenClaw は VPS 上で UDP `14550` を待ち受ける
- OpenClaw は起動直後に heartbeat を待ってから処理を始める

最小構成:

- WSL 側 SITL: `--out=udp:<VPSのTailscaleホスト名>:14550`
- VPS 側 OpenClaw: `udpin:0.0.0.0:14550`

## OpenClaw 実装時の指針

OpenClaw 側の最初の実装では、責務を絞るべきである。

- 接続文字列を設定で差し替えられるようにする
- 起動直後に `wait_heartbeat()` 相当の同期を取る
- heartbeat を受信したら `target_system`、`target_component`、`flightmode` を記録する
- 初回は監視だけに留め、mode change や command 送信は後段で追加する
- 失敗時は endpoint と例外内容をログへ残す

最初の接続文字列は次でよい。

```python
'udpin:0.0.0.0:14550'
```

## 注意点

- UDP は待ち受け側と送信先の組み合わせを間違えると何も見えない
- VPS 側で待ち受ける場合、SITL の `--out` には VPS 側の Tailscale status で確認できる名前を指定する
- WSL 側のホスト名を `--out` に指定しても、VPS への送信にはならない
- OpenClaw と別ツールを同時利用するなら、SITL の `--out` を複数指定する
- TCP `5760` を基準に考えないこと。この構成で最初に確認すべきは UDP の片方向送信である

## トラブルシュート

### VPS 側で heartbeat を受信できない

- WSL 側 SITL に `--out=udp:<VPSのホスト名>:14550` が付いているか確認する
- VPS 側で `udpin:0.0.0.0:14550` を待ち受けているか確認する
- WSL と VPS のホスト名を取り違えていないか確認する
- Tailscale ACL やホスト側ファイアウォールで UDP `14550` が遮断されていないか確認する
- `status` の `MasterIn` が増えない場合は、VPS 側に MAVLink が届いていないと考える

### MAVProxy は起動するが mode 名が出ない

- heartbeat が到達していない可能性が高い
- `Waiting for heartbeat` のままなら未接続と判断する
- SITL の起動コマンドに指定した `--out` の IP とポートを見直す

### Python スクリプトが `wait_heartbeat()` で止まる

- OpenClaw と同じく、受信ポートに何も届いていない状態である
- まず VPS 上で MAVProxy 受信確認を通し、その後に Python 確認へ進む
- 送信元は WSL 上の SITL、受信先は VPS 上の `udpin:0.0.0.0:14550` であることを再確認する

## まとめ

この構成で最初に成立させるべき経路は次の 1 本である。

- WSL 上の SITL が VPS のホスト名へ UDP で telemetry を送る

確認完了の条件は次のとおり。

1. WSL 上の SITL を `--out=udp:<VPSのホスト名>:14550` 付きで起動できる
2. VPS 上の MAVProxy または Python が heartbeat を受信できる
3. `target_system`、`target_component`、`flightmode` を取得できる

ここまで確認できれば、OpenClaw 側には同じ待ち受け設定を組み込めばよい。