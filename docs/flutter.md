# Flutter開発環境 (flutter-dev: harmonic)

[Web開発環境](web.md) と同じく、コンテナで開発サーバーとビルドを動かし、
Macで画面を確認する。対象はWebとAndroid。
[harmonic](https://github.com/0-0mfuji/harmonic) を `dev flutter harmonic` で開く。

## 構成と、入れるもの

| 層 | 内容 | 管理するところ |
| --- | --- | --- |
| コンテナ | Flutter / Dart / DevTools、Node.js、corepack/pnpm、Turso CLI、JDK 21、Android SDK / NDK、Linuxビルドツール、git-lfs、gh、sqlite3 | 別リポジトリ `dotfile_infra/provision` |
| プロジェクト | Flutterパッケージ、Hono / TypeScript、DBドライバー、テストツール | `pubspec.yaml` / `pubspec.lock`、`package.json` / pnpmのlockfile |
| Mac | ブラウザ、Android Studio、Android Emulator、platform-tools (`adb`) | Homebrew / Android StudioのSDK Manager |
| 秘密 | Tursoの認証、DBトークン、APIキー | Git管理外の環境変数・設定ファイル |

Flutter SDKはDartを同梱する。Macにはブラウザとエミュレーター用の道具を入れ、
Flutter・Node.js・JDKによるビルドはコンテナで行う。
WebはSSHトンネルでプレビューし、Androidはコンテナで作ったAPKをMacのエミュレーターに入れる。

## ゼロから作る手順

### 1. コンテナを作る (サーバー上)

`~/dotfile_infra/terraform.tfvars` の `dev_instances` に追加する。
`ip` はネットワーク内で重ならない値を選び、MacのSSH設定と合わせる。

```hcl
flutter = {
  cpu       = 4
  memory    = "16GiB"  # 共通のDeepSeek Harnessのビルドにも必要
  disk_size = "80GiB"
  ip        = "<コンテナ用の固定IPv4>"
}
```

```sh
cd ~/dotfile_infra
tofu plan       # 追加1、既存コンテナの変更・削除がないことを確認
tofu apply
./provision/run flutter-dev
```

構築処理は `provision/flutter.sh`。`versions.env` でFlutterの版・公式Gitコミット、
Turso CLIの版・SHA-256、Android Command-line Toolsの配布番号・SHA-256とSDK/NDKの版を固定する。
Flutter SDKはdevユーザー所有の `~/sdk/flutter-<version>` に置き、
`/usr/local/bin/flutter` と `dart` からSSH非対話シェルやエージェントでも使える。
Android SDKは `~/Android/Sdk` に置く。初回にSDKのライセンス確認が求められた場合は、
Macから次を実行して確認・承諾し、構築処理を再実行する。

```sh
ssh -t flutter-dev '~/Android/Sdk/cmdline-tools/latest/bin/sdkmanager --licenses'
```

### 2. MacのSSH設定

`~/.ssh/config.local` (Git管理外):

```sshconfig
Host flutter-dev
    HostName <コンテナ用の固定IPv4>
    User dev
    ProxyJump dev-server
```

`config/projects.conf` の登録:

```text
flutter/harmonic  flutter-dev  ~/src/harmonic  flutter-dev  git@github.com:0-0mfuji/harmonic.git  git  -  7357=flutter
```

`7357=flutter` はFlutter Webを起動し、SSHトンネルでMacのブラウザに開く指定。
web-devの `5173=dev:web` と同じ `dev --preview` を使う。

### 3. cloneとFlutterアプリの用意

```sh
dev --zed flutter harmonic
```

初回は `~/src/harmonic` に自動cloneする。2026-10-22時点のharmonicは空のリポジトリのため、
まだプレビューできるアプリがない。アプリをルートに置く場合の初期化例 (コンテナ内):

```sh
cd ~/src/harmonic
flutter create --platforms=web,android --project-name harmonic .
flutter pub get
```

既にアプリがある場合は作り直さず、`flutter pub get` だけを実行する。
サブディレクトリにアプリを置く設計にした場合は `projects.conf` のpathも合わせる。

### 4. MacのブラウザでWebを確認する

```sh
dev --preview flutter harmonic
# または Zed + 共通Web UI + Flutter Web を開く
dev flutter harmonic
```

コンテナの `flutter run -d web-server --web-hostname 127.0.0.1 --web-port 7357` を起動し、
Macのブラウザに開く。MacにFlutterやChromeDriverを入れる必要はない。
初回のコンパイルは待ち時間が長い。ログはコンテナの `~/.cache/preview-7357.log`。
ローカルポートが使用中なら別の空きポートで開く。トンネルの寿命は既定4時間 (`DEV_WEB_TUNNEL_TTL`)。

`web-server` のデバッグ機能には制限がある。対話的に再起動・ログを確認するときは、
自動起動したプロセスをコンテナの `ss -ltnp '( sport = :7357 )'` で確認して停止し、
コンテナのターミナルで同じ `flutter run` コマンドを実行する。
ソースを変更したら、そのターミナルで `r` / `R` の案内に従う。

### 5. MacにAndroidエミュレーターを用意する

Macで次を実行する (Android Studioが既にある場合はインストール不要)。
Android Studioとシステムイメージを取得するため、事前にMacの空き容量を確保する。

```sh
brew install --cask android-studio
open -a 'Android Studio'
```

初回ウィザードとSDK Managerで次を導入し、表示されるライセンスを確認・承諾する。

- Android SDK Platform-Tools
- Android Emulator
- Android API 36のシステムイメージ

このMacはApple Siliconなので、システムイメージは `arm64-v8a` を選ぶ。
Intel Macでは `x86_64` を選ぶ。Android StudioのDevice ManagerでPixelなどの端末を作り、起動する。
MacではSDKの標準配置 `~/Library/Android/sdk` を使う。

```sh
# Macで確認
"$HOME/Library/Android/sdk/emulator/emulator" -list-avds
"$HOME/Library/Android/sdk/platform-tools/adb" devices
```

`emulator-5554 device` のように表示されれば起動済み。
Android StudioのDevice Managerから起動でき、Flutter SDKをMacに入れずに使える。

### 6. コンテナでAPKを作り、Macのエミュレーターに入れる

Macで実行する。先にエミュレーターを1台起動しておく。

```sh
ssh dev-server 'systemd-inhibit --what=sleep --why="Flutter Android build" \
  incus exec flutter-dev --user 1000 --group 1000 --cwd /home/dev/src/harmonic \
  --env HOME=/home/dev -- bash -lc "flutter pub get && flutter build apk --debug --target-platform android-arm64"'
mkdir -p "$HOME/Library/Caches/dev/harmonic"
scp flutter-dev:src/harmonic/build/app/outputs/flutter-apk/app-debug.apk \
  "$HOME/Library/Caches/dev/harmonic/app-debug.apk"
"$HOME/Library/Android/sdk/platform-tools/adb" -e install -r \
  "$HOME/Library/Caches/dev/harmonic/app-debug.apk"
```

インストール後はエミュレーターのアプリ一覧から起動する。
複数のエミュレーターが起動中なら `-e` を `-s emulator-5554` などの実際のserialに変える。
Intel Macではビルド引数を `--target-platform android-x64` にする。
変更後は同じ手順で再ビルド・再インストールする。このAPK転送方式はホットリロードを行わない。
エミュレーターのデータを維持して更新するため `adb install -r` を使う。

### 7. Hono / Tursoの用意

Honoの依存はプロジェクト側で管理する。Node.jsバックエンドを新しく作る例 (コンテナ内):

```sh
cd ~/src/harmonic
pnpm create hono@latest backend   # nodejsテンプレートを選択
cd backend
pnpm install
pnpm dev
```

既存の `package.json` がある場合は、その構成とlockfileを使う。
Tursoの初回認証は `turso auth login`。DBトークンはHono側で保持する。
Flutterアプリに管理用トークンを埋め込まない。

バックエンドをコンテナの `127.0.0.1:8787` で起動した場合、Macで次のトンネルを維持する。
Honoの待受ポートはプロジェクト側で設定する。

```sh
ssh -N -L 8787:127.0.0.1:8787 flutter-dev
```

| クライアント | APIの接続先 |
| --- | --- |
| MacのWebブラウザ | `http://127.0.0.1:8787` |
| MacのAndroidエミュレーター | `http://10.0.2.2:8787` (Macのループバックへの専用アドレス) |

接続先をDartの `String.fromEnvironment` などで切り替えられるようアプリ側に実装する。
WebではHono側に実際のプレビューoriginを許可するCORS設定が必要。
Androidでは開発用HTTPを使うなら `android/app/src/debug/AndroidManifest.xml` のapplicationに
`android:usesCleartextTraffic="true"` を設定する。製品版はHTTPSを使う。
`10.0.2.2` はAndroidエミュレーター専用であり、実機では同じ接続先を使えない。

## 追加するとよいもの

- API入力検証: [HonoのValidatorとZod](https://hono.dev/docs/guides/validation)。
- DBスキーマとマイグレーション管理: [Drizzle + Turso](https://orm.drizzle.team/docs/tutorials/drizzle-with-turso)。
- `flutter analyze` / `flutter test` とHono側のテストをCIに組み込む。

これらはアプリの要件に合わせてプロジェクトに追加する。

## 動作確認

| 確認 | 期待する結果 |
| --- | --- |
| コンテナ: `flutter --version; dart --version; turso --version; java -version` | 版が出る |
| コンテナ: `flutter doctor -v` | Android toolchainが利用可能。コンテナにChrome・Android Studio・GUI表示環境がなくても上記のWebサーバー・APKビルド方式は使える |
| コンテナ: `flutter analyze; flutter test; flutter build web` | アプリ作成後に通る |
| Mac: `dev --preview flutter harmonic` | トンネル先がHTTP 200、画面が表示される |
| Mac: `adb devices` (上記のフルパス) | エミュレーターがdeviceとして見える |
| APKの転送と `adb install -r` | Success、エミュレーターで起動できる |

長時間のサーバー側ビルドは `systemd-inhibit` で自動Suspendを抑止する。
Mac側もAPK取得中はスリープさせない。

## うまくいかないとき

| 症状 | 確認 |
| --- | --- |
| Flutterプレビューの前提不足 | 空のリポジトリにアプリを作成したか。`pubspec.yaml` と `web/` があるか |
| プレビューが起動しない | `~/.cache/preview-7357.log`。手動 `flutter run -d web-server` でエラーを確認 |
| SDKライセンスのエラー | `sdkmanager --licenses` で確認し、構築処理を再実行 |
| `INSTALL_FAILED_NO_MATCHING_ABIS` | Apple Siliconはarm64、Intelはx64のAPKをビルドしたか |
| `adb` が見つからない | Mac側SDK ManagerでPlatform-Toolsを入れたか。標準配置でなければパスを変更 |
| AndroidからAPIに接続できない | SSHトンネル、`10.0.2.2`、Honoのポート、debug用HTTP設定 |
| WebからAPIに接続できない | SSHトンネルとHonoのCORS。ローカルポートが変わった場合はoriginも変更 |

参考: [Flutter Web開発](https://docs.flutter.dev/platform-integration/web/setup)、
[Flutter Android開発](https://docs.flutter.dev/platform-integration/android/setup)、
[Android Emulator](https://developer.android.com/studio/run/emulator-commandline)。

## 実環境での確認 (2026-10-22)

- `flutter-dev` を新規作成。OpenTofuは追加1、変更0、削除0。
- Flutter 3.47.5、Dart 3.13.4、Node 22.23.4、Turso CLI 1.0.34を導入。
- JDK 21、Android API 36 / Build Tools 36.0.0 / NDK 28.2を導入し、`flutter doctor -v` のAndroid toolchainが正常。
- 一時アプリで `flutter analyze`、`flutter test`、`flutter build web` が成功。
- 同じ一時アプリで `flutter build apk --debug --target-platform android-arm64` が成功 (初回約268秒)。SDK XMLの版に関する警告は出たが、APK生成は成功した。
- `scripts/open-preview` でFlutter Webを起動し、SSHトンネル経由でMacからHTTP 200とアプリのHTMLを確認。
- 一時ディレクトリのHono + Node.js Adapterを起動し、HTTPでJSON応答を確認。
- harmonicのcloneは完了。リポジトリにはまだアプリを作成していない。

MacのAndroid Studio / SDK / 仮想端末は未導入で、エミュレーター上の動作確認は未実施。
このMacでは作業時に空き容量不足を確認したため、先に容量を確保してから上の手順で導入する。
