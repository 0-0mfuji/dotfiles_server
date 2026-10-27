# Arch Linux クライアント

Arch LinuxをThin Clientとして使い、ZedからDevelopment Server上のIncusコンテナに接続する手順。
サーバーの構築とコンテナ管理は引き続き `dotfile_infra` が担当する。

## 初回セットアップ

1. 必要なクライアントツールを導入する。ZedとTailscaleも別途インストールし、必要ならTailnetにログインする。

   ```sh
   sudo pacman -S git openssh bash python coreutils grep gawk sed procps-ng openbsd-netcat
   ```

2. このリポジトリをcloneして、Arch用セットアップを実行する。

   ```sh
   git clone git@github.com:0-0mfuji/dotfiles_server.git ~/home/dotfiles_server
   cd ~/home/dotfiles_server
   ./install.sh arch
   ```

3. SSH鍵を `~/.ssh/` に配置する。秘密鍵はGit管理しない。必要なら `ssh-agent` を起動して鍵を登録する。
   ZedのSSH remoteと `dev` の自動cloneでagent forwardingを使う場合、接続元のagentにGitHub鍵を追加する。

4. `~/.ssh/config.local` に、親サーバーと開発コンテナの接続先を設定する。

   ```sshconfig
   Host dev-server
       HostName <親サーバーのTailnet IPまたはMagicDNS名>
       User <ユーザー名>
       IdentityFile ~/.ssh/<秘密鍵>
       IdentitiesOnly yes
       ForwardAgent yes

   Host raspi
       HostName <PiのTailnet IPまたはMagicDNS名>
       User <ユーザー名>
       IdentityFile ~/.ssh/<秘密鍵>
       IdentitiesOnly yes

   Host os-dev
       HostName 10.10.0.13
       User dev
       ProxyJump dev-server
       IdentityFile ~/.ssh/<秘密鍵>
       IdentitiesOnly yes
       StrictHostKeyChecking no
       UserKnownHostsFile /dev/null
   ```

   他のコンテナも必要に応じて追加する。`HostName` は `dotfile_infra` の `terraform.tfvars` にあるIPと合わせる。
   `~/.ssh/config` にIncludeを追加できなかった場合は、セットアップが表示した2行をファイルの先頭に加える。

5. `~/.config/dev/local.env` を編集する。サーバーがWoLで起動できる構成なら、`DEV_SERVER_MAC` と `RASPI_HOST` を実値にする。
   WoLを使わない場合は `RASPI_HOST` と `DEV_SERVER_MAC` を空にして、サーバーは事前に起動しておく。

6. `~/.local/bin` がPATHにあることを確認し、SSH接続してからZed Remote Developmentを試す。

   ```sh
   ssh dev-server
   ssh os-dev
   dev --zed os sota
   ```

   `dev os sota` はZedに加えてWeb UI・QR・設定済みプレビューも起動する。Zedだけなら `dev --zed os sota` を使う。

## 注意点

- `./install.sh arch` はSSH設定と `dev` コマンドを用意する。Zed、Tailscale、SSH鍵のインストールやログインは行わない。
- `dotfile_infra` はArchクライアントにcloneする必要はない。親サーバー上のIncus環境を管理するリポジトリ。
- 親サーバーが停止中のとき、`dev` はRaspberry Pi経由でWoLする。Piが無い場合はサーバーを手動で起動し、`dev` を使う。
- `dev` がGitHubからprivate repositoryをcloneする場合、`ForwardAgent yes` と接続元の `ssh-agent` に鍵が必要。
- Webブラウザ起動には `xdg-open` を使う。必要なら `sudo pacman -S xdg-utils` で導入する。無い場合はURLを出力する。
