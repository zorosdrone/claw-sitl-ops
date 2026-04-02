# 導入手順: XServer VPS OpenClaw + WSL SITL

このドキュメントは、次の構成でこの Skill を動かすための導入手順です。

- OpenClaw は XServer VPS 上で動かす
- ArduPilot SITL は Windows PC の WSL 上で動かす
- 両方とも TailScale 導入済み

構成図は [docs/12_分離構成図_XServerVPS_OpenClaw_WSL_SITL.md](12_分離構成図_XServerVPS_OpenClaw_WSL_SITL.md) を参照してください。

## 1. 先に理解しておく制約

この構成で使えるもの:
- `!sitl start`
- `!sitl stop`
- `!sitl status`
- `!sitl arm`
- `!sitl takeoff 10`
- `!sitl mode GUIDED`
- `!sitl param get ...`
- `!sitl param set ...`

理由:
- [scripts/sitl_dispatch.sh](../scripts/sitl_dispatch.sh) は `SITL_REMOTE_SSH_TARGET` を設定すると、start/stop を SSH 経由のリモート実行に切り替えるため

前提条件:
- VPS から WSL 側へ SSH 接続できること
- もしくは Windows 側の SSH で WSL コマンドを代理実行できること

## 2. 事前準備

### 2-1. XServer VPS 側で確認すること

1. OpenClaw 最新版が導入済みであること
2. TailScale が接続済みであること
3. bash と Python 3 が使えること

確認例:

```bash
python3 --version
bash --version
tailscale status
```

### 2-2. Windows PC の WSL 側で確認すること

1. WSL が使えること
2. WSL 内で TailScale 到達性が確保できていること
3. ArduPilot リポジトリがあること
4. `sim_vehicle.py` を実行できること
5. SSH の受け口が用意できていること

確認例:

```bash
python3 --version
bash --version
ls ~/ardupilot/Tools/autotest/sim_vehicle.py
```

注意:
- TailScale が Windows ホスト側に入っているだけで、VPS から WSL 上の MAVLink ポートへ到達できるとは限りません
- 必要に応じて、WSL から見た待受アドレスや Windows 側のポート中継も確認してください
- SSH の入口は、WSL 直通でも Windows 側経由でも構いません

## 3. XServer VPS 側に Skill を配置する

XServer VPS 側の OpenClaw workspace に、このリポジトリを `skills/sitl-ops` として配置します。

例:

```bash
mkdir -p ~/.openclaw/workspace/skills
cp -r /path/to/claw-sitl-ops ~/.openclaw/workspace/skills/sitl-ops
```

## 4. XServer VPS 側で Skill 用仮想環境を作成する

```bash
cd ~/.openclaw/workspace
bash skills/sitl-ops/scripts/setup_venv.sh
```

成功時の想定:
- `.venv` が作成される
- `pymavlink`、`empy==3.3.4`、`MAVProxy` が入る

## 5. XServer VPS 側に設定ファイルを作成する

毎回 `export` しなくて済むように、設定ファイルを作成します。

```bash
cd ~/.openclaw/workspace
cp skills/sitl-ops/sitl-ops.remote.env.example .sitl-ops.env
```

その後、`.sitl-ops.env` を環境に合わせて編集します。

最低限必要な項目:

```bash
SITL_VENV_PYTHON="$HOME/.openclaw/workspace/.venv/bin/python"
SITL_MASTER="udp:100.64.10.20:14550"
SITL_REMOTE_SSH_TARGET="user@100.64.10.20"
SITL_REMOTE_AP_ROOT="$HOME/ardupilot"
SITL_REMOTE_AP_VENV_ACTIVATE="$HOME/venv-ardupilot/bin/activate"
SITL_REMOTE_START_ARGS="-v Copter -L Kawachi --no-mavproxy --out=0.0.0.0:14550"
SITL_REMOTE_LOG="/tmp/sitl_copter.log"
```

補足:
- `SITL_MASTER` は OpenClaw から見た WSL 側の MAVLink 接続先です
- `SITL_REMOTE_SSH_TARGET` は `!sitl start` / `!sitl stop` の SSH 接続先です
- WSL に直接 SSH できない場合は、Windows 側 OpenSSH の接続先を書いても構いません

## 6. SSH 接続確認を行う

VPS 側から、設定した接続先へ SSH できることを確認します。

例:

```bash
ssh user@100.64.10.20
```

ここでログインできない場合、`!sitl start` / `!sitl stop` は動きません。

## 7. `!sitl start` で WSL 側の SITL を起動する

設定ファイルを置いた後は、VPS 側から次を実行します。

```bash
cd ~/.openclaw/workspace
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl start"
```

期待結果:
- `mode: remote` を含む JSON が返る
- `status` が `started` または `already_running` になる
- 指定した `SITL_REMOTE_LOG` が返る

WSL 側で手動確認したい場合は、ArduPilot ディレクトリへ移動して同等コマンドを直接確認できます。

例:

```bash
cd ~/ardupilot
```

SITL を起動します。

最小例:

```bash
./Tools/autotest/sim_vehicle.py -v Copter -L Kawachi --no-mavproxy
```

分離構成では、OpenClaw 側から届くように MAVLink の出力先を明示した方が安全です。

例:

```bash
./Tools/autotest/sim_vehicle.py -v Copter -L Kawachi --no-mavproxy --out=0.0.0.0:14550
```

補足:
- 実際にどの引数が有効かは、手元の ArduPilot バージョンと WSL ネットワーク構成に依存します
- `--out` の向きや bind の扱いは環境差があるため、必要なら `mavproxy.py` や追加転送設定で調整してください

## 8. VPS から WSL への到達性を確認する

最初に確認すべきなのは、OpenClaw 側から WSL 上の SITL に heartbeat を取りにいけるかです。

続けて、VPS 側で status を実行します。

```bash
cd ~/.openclaw/workspace
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl status"
```

期待結果:
- heartbeat を取得できる
- JSON で状態が返る

失敗した場合の確認点:
1. WSL 側で SITL が起動しているか
2. WSL 側で MAVLink が期待ポートで待ち受けているか
3. TailScale アドレスが正しいか
4. Windows / WSL 間のポート到達性に問題がないか

## 9. コマンド単位のテスト手順

以下はすべて XServer VPS 側で実行します。

### 9-1. start

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl start"
```

確認点:
- `action: start`
- `mode: remote`
- `status: started` または `already_running`

### 9-2. status

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl status"
```

確認点:
- `mode` が取得できる
- `armed` が返る
- `position` が返る

### 9-3. arm

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl arm"
```

確認点:
- `ok: true`
- `status.armed: true`

### 9-4. takeoff

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl takeoff 10"
```

3 から 5 秒後に再確認:

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl status"
```

確認点:
- `mode` が `GUIDED`
- 高度が上がる

### 9-5. mode

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl mode GUIDED"
```

### 9-6. param get

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl param get ARMING_CHECK"
```

### 9-7. param set

先に現在値を記録します。

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl param get ARMING_CHECK"
```

その後に変更します。

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl param set ARMING_CHECK 1"
```

### 9-8. stop

```bash
bash skills/sitl-ops/scripts/sitl_dispatch.sh "!sitl stop"
```

確認点:
- `action: stop`
- `mode: remote`
- `status: stopped`

## 10. 運用上の推奨フロー

この構成では次の運用が現実的です。

1. VPS 側で `sitl-ops.remote.env.example` を元に `.sitl-ops.env` を置く
2. OpenClaw から `!sitl start` を実行する
3. `status`、`arm`、`takeoff` などを実行する
4. 停止時は `!sitl stop` を実行する

## 11. よくある詰まりどころ

### heartbeat が返らない

確認順:
1. WSL 側で SITL が起動しているか
2. VPS 側で `SITL_MASTER` が localhost のままになっていないか
3. TailScale アドレスが変わっていないか
4. WSL 側の MAVLink 出力が VPS から到達可能か

### WSL 内では動くが VPS から見えない

主な原因候補:
- WSL の待受が localhost に閉じている
- Windows と WSL のネットワーク境界で転送できていない
- TailScale で見えているのが Windows ホストのみで、WSL 側ポートが露出していない

### `!sitl start` が失敗する

主な原因候補:
- `SITL_REMOTE_SSH_TARGET` が誤っている
- VPS から SSH ログインできない
- WSL 側で `sim_vehicle.py` のパスが違う
- `SITL_REMOTE_AP_VENV_ACTIVATE` が違う

まずは VPS 側から通常の SSH ログインが成功することを確認してください。

## 12. 導入完了の判定基準

次を満たせば、この分離構成での導入は完了です。

1. XServer VPS 側で Skill の `.venv` が作成できる
2. VPS 側から WSL 側へ SSH できる
3. VPS 側で `!sitl start` が成功する
4. VPS 側で `!sitl status` が成功する
5. VPS 側で `!sitl arm` が成功する
6. VPS 側で `!sitl takeoff 10` 後に高度上昇を確認できる
7. VPS 側で `!sitl stop` が成功する

## 13. 将来的な改善候補

この構成をより使いやすくするなら、次の拡張が有効です。

1. `SITL_MASTER` を Discord コマンドや OpenClaw 設定から切り替え可能にする
2. 接続先の疎通確認コマンドを Skill に追加する
3. WSL 直通 SSH と Windows 経由 SSH の設定テンプレートを分ける