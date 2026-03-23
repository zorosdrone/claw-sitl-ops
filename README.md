# openclaw-skill-sitl-ops

ArduPilot SITL を MAVLink 経由で操作するための OpenClaw Skill です。
（`status` / `arm` / `takeoff` / `mode` / `param get/set` など）

## ファイル構成
- `SKILL.md`
- `scripts/sitl_mav.py`
- `scripts/sitl_dispatch.sh`
- `scripts/setup_venv.sh`
- `sitl-ops.local.env.example`
- `sitl-ops.remote.env.example`

## 使い方
このフォルダを OpenClaw の skills パス配下に配置し、`SKILL.md` の手順に従って利用してください。

詳細な導入手順とテスト手順は [docs/10_導入手順.md](docs/10_導入手順.md) を参照してください。

想定構成図は [docs/11_想定構成図.md](docs/11_想定構成図.md) を参照してください。

XServer VPS 上の OpenClaw と、Windows PC の WSL 上の SITL を TailScale で接続する分離構成は [docs/12_分離構成図_XServerVPS_OpenClaw_WSL_SITL.md](docs/12_分離構成図_XServerVPS_OpenClaw_WSL_SITL.md) と [docs/13_導入手順_XServerVPS_OpenClaw_WSL_SITL.md](docs/13_導入手順_XServerVPS_OpenClaw_WSL_SITL.md) を参照してください。

設定ファイルのサンプルは、同一ホスト構成なら [sitl-ops.local.env.example](sitl-ops.local.env.example)、VPS と WSL の分離構成なら [sitl-ops.remote.env.example](sitl-ops.remote.env.example) を参照してください。

---

## 初期構築（OpenClaw TUI）

最初の実装は `openclaw tui` で、対話しながら「まず動く雛形」を生成して作りました。

### 初期プロンプト（再現用テンプレ）

```text
ArduPilot SITL を OpenClaw から操作する Skill を作って。
MAVLink 経由で以下を実行できるようにして:
- status
- arm/disarm
- takeoff
- mode 変更
- param get/set

必要ファイル:
- SKILL.md
- scripts/sitl_mav.py
- scripts/sitl_dispatch.sh
- scripts/setup_venv.sh

出力は Discord で扱いやすいよう JSON で返して。
まずは最小構成で動くところまで作って。
```

初期フェーズで意識した点：
- MAVLink ベースの SITL 操作に必要な `SKILL.md` と Python / dispatch スクリプトを先に作る
- コアコマンド（`status`, `arm`, `takeoff`, `mode`, `param get/set`）を優先実装する
- Discord 側で整形しやすいよう、返却は機械可読（JSON）を基本にする

この段階の目標は機能網羅ではなく、
`コマンド -> MAVLink操作 -> 状態観測` の最短 E2E をまず成立させることでした。

---

## Discord での育成プロセス（Try & Error）

TUI で土台を作った後は、Discord 上での実運用を回しながら改善しました。

基本ループ：
1. チャットから実コマンド実行（例: `!sitl status`、移動、ミッション upload/start）
2. 成功/失敗を観測
3. skill/scripts を修正
4. Discord から再テスト
5. 小さくコミット

### ログに基づく主な改善点
- `!sitl status` に Google Maps URL（`map_url`）を追加し、位置確認をワンクリック化
- 初期離陸フローを `NAV_TAKEOFF`（`sitl_mav.py takeoff`）中心に統一し、arm/disarm レースを回避
- ミッション系ワークフローを実地検証
  - 正方形ミッション upload
  - 星形ミッション upload
  - `AUTO` でミッション開始
  - 実行後のテレメトリ/状態報告
- オペレータ指示に応じて、定期ステータス報告の開始/停止や出力内容を調整

要するに、**TUI で土台を作り、Discord で信頼性と UX を育てた**構成です。

---

## 会話ログ由来の簡易タイムライン

- **Step 1: 土台作成（TUI）**
  - SITL 操作用の初期 Skill 一式を生成
  - 基本コマンド群を実装

- **Step 2: 状態可視化の改善（Discord）**
  - `!sitl status` に地図 URL を追加
  - 運用時の確認負荷を削減

- **Step 3: 離陸フローの安定化（Discord）**
  - arm/disarm 問題を対話で切り分け
  - `NAV_TAKEOFF` ベースに修正し、手順を Skill に反映

- **Step 4: ミッション運用の検証（Discord）**
  - 正方形/星形ミッションの作成・upload・開始を実施
  - 実行中/実行後の状態報告まで確認

- **Step 5: 運用機能の調整（Discord）**
  - 定期報告の開始/停止、出力粒度の調整
  - 実際の使い方に合わせて運用性を改善
