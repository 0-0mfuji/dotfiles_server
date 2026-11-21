# 学習用コンテナ

Mac で `dev learn` を実行すると、教材検索・メモ・NAS 接続の案内が表示され、Zed で `~/learn`、ブラウザで DeepSeek Harness（DSH）が開く。DSH だけを開くには `dev --web learn`。初回は Web UI の設定で利用するプロバイダー、モデル、認証情報を設定する。

## 教材を探す・疑問を記録する

Zed のリモートターミナル、または `ssh learn-dev` で実行する。

```sh
fd -i '循環|cardio' ~/learn/materials
rg -in '心拍出量' ~/learn/notes ~/learn/materials
pdfgrep --cache -Hrin '心拍出量' ~/learn/materials
```

Rust 製の `fd` と `rg` でファイル名とテキスト本文を検索できる。`pdfgrep` は PDF 本文の一致箇所をファイル名・ページ番号とともに表示し、抽出したテキストを再検索時に再利用する。[pdfgrep のマニュアル](https://pdfgrep.org/doc.html)

画像だけの PDF は OCR 済みのコピーを作成してから検索する。原本と出力には別のパスを指定する。

```sh
ocrmypdf -l jpn+eng --skip-text ~/learn/materials/講義.pdf ~/learn/materials/講義-ocr.pdf
```

疑問は Zed で `notes/質問.md` に追記する。DSH に「教材から心拍出量を調べて、参照したページと残った疑問を学習メモに追記して」と依頼することもできる。メモはコンテナ内に保存されるため、コンテナを作り直す前に `~/learn/notes` をバックアップする。

## DSH から PDF の該当ページを開く

`dev learn` または `dev --web learn` で DSH を開き、「心拍出量の説明があるページを探して、Mac で開けるリンクを付けて」と依頼する。回答のリンクをクリックすると、PDF ビューアが `#page=N` に対応するブラウザでは該当ページが開く。ページ番号は表紙を含めた PDF ファイル内の順序。

リンクはリモートターミナルでも作れる。

```sh
learn-material 'nas/循環器 講義.pdf' 12
```

教材ディレクトリからの相対パスか、コンテナ内の絶対パスを指定する。ページ番号を省略すると、PDF 全体や PNG・JPEG・WebP 画像のリンクを作れる。教材は Mac のループバックに限定した SSH トンネルで配信する。トンネルが切れたら `dev --web learn` を再実行する。

## Synology NAS の教材を取り込む

DSM の「コントロールパネル → ファイルサービス → SMB」で SMB を有効にする。教材用共有フォルダへの読み取り権限を持つアカウントを使う。コンテナから到達できる NAS の LAN アドレスか DNS 名、共有名、ユーザー名を指定する。[Synology の SMB 設定](https://kb.synology.com/en-global/DSM/help/SMBService/smbservice_smb_settings?version=7)

```sh
cd ~/learn/materials/nas
smbclient '//NASのホスト名/共有名' -U 'ユーザー名'
```

パスワードはプロンプトに直接入力する。`smb: \>` で `ls`、`cd "講義資料"`、`get "講義.pdf"` のように操作する。同じフォルダ内の PDF をまとめて取り込むには `mget *.pdf` を使う。取得した教材は `~/learn/materials/nas` から検索できる。NAS 側で資料が更新された場合は必要なファイルを取り込み直す。

## 初回のコンテナ作成

設定の変更を Mac から両リポジトリのリモートへ公開し、Development Server の `~/dotfile_infra` で `git pull --ff-only` する。既存の `terraform.tfvars` の `dev_instances` に `terraform.tfvars.example` の `learn` を追加する。`ip` には開発ネットワークの空きアドレスを指定する。DSH の初回ビルド用にメモリ上限は 16 GiB とする。

```sh
cd ~/dotfile_infra
tofu plan -out=learn.tfplan
# learn-dev の追加だけであることを確認してから実行
tofu apply learn.tfplan
incus exec learn-dev -- cloud-init status --wait
systemd-inhibit --what=sleep --mode=block ./provision/run learn-dev
```

Mac の `~/.ssh/config.local` に設定する。`HostName` は `learn.ip` と同じ値にする。

```sshconfig
Host learn-dev
    HostName <learnの固定IPv4>
    User dev
    ProxyJump dev-server
```

`dev learn` で起動する。DSH の Web UI は既存の SSH トンネル経由で開く。
