# MacBook

MacBookはThin Client。入れるのは Zed / OpenSSH / SSH鍵 / Tailscale / このdotfiles だけ。

## 目次

- [初回セットアップ](#初回セットアップ)
- [Macをリセットしたときの復旧](#macをリセットしたときの復旧)

## 初回セットアップ

1. TailscaleとZedを入れ、Tailscaleにログインする。
2. このリポジトリをcloneしてインストールする。

   ```sh
   git clone git@github.com:0-0mfuji/dotfiles_server.git ~/home/dotfiles_server
   cd ~/home/dotfiles_server
   ./install.sh macos
   ```

   シンボリックリンクを張るだけで、既存ファイルは上書きしない。

3. `~/.ssh/config` の先頭に次の2行を足す。`~/.ssh/config` がシンボリックリンクの場合、
   インストーラは自動編集しない (別のdotfilesを壊さないため)。

   ```
   Include ~/.ssh/config.d/dotfiles
   Include ~/.ssh/config.local
   ```

4. Git管理外の2ファイルを編集する。

   | ファイル | 内容 |
   | --- | --- |
   | `~/.ssh/config.local` | 実際のHost定義 (IP, ProxyJump, User等) |
   | `~/.config/dev/local.env` | `DEV_SERVER_HOST` / `DEV_SERVER_MAC` / `RASPI_HOST` |

   `~/.ssh/config.local` の例 (コンテナはDevelopment Server経由で入る):

   ```
   Host dev-server
       HostName 100.x.x.x            # Tailscale IP (自宅内でも外出先でも同じ)
       User <user>
       IdentityFile ~/.ssh/<key>
       IdentitiesOnly yes

   Host raspi
       HostName 100.x.x.x
       User <user>
       IdentityFile ~/.ssh/<key>
       IdentitiesOnly yes

   Host os-dev
       HostName 10.10.0.13           # dotfile_infra の terraform.tfvars の ip と合わせる
       User dev
       ProxyJump dev-server
       IdentityFile ~/.ssh/<key>
       IdentitiesOnly yes
       StrictHostKeyChecking no      # コンテナは作り直すとホスト鍵が変わるため
       UserKnownHostsFile /dev/null

   Host *
       AddKeysToAgent yes            # dev がGitHubからcloneするときのエージェント転送に必要
       UseKeychain yes
       IgnoreUnknown UseKeychain
   ```

5. **Zedのエージェント**は、`./install.sh macos` が、`~/.config/zed/settings.json` の `agent_servers` に、
   [macos/zed/agent_servers.json](../macos/zed/agent_servers.json) のうち**無いものだけ**を追記する
   (DeepSeek Harness / Claude Code (container) / Codex (container))。既にある項目、コメント、Zedが保存した
   モデルの選択 (`default_config_options`) は、変更しない。書き換える前に、バックアップを作る。
   単独で実行するには `python3 macos/zed/apply-settings`。
6. `~/.local/bin` をPATHに通し (zshは自動、fishは `fish_add_path ~/.local/bin`)、`dev <target>` で確認する。

## Macをリセットしたときの復旧

### リセット前に退避する (最重要)

次の3つは**Gitに入っていない**ので、パスワードマネージャーや暗号化したバックアップに保管する。

| 退避するもの | 理由 |
| --- | --- |
| `~/.ssh/<key>` (秘密鍵) | GitHub・サーバー・Raspberry Piへの鍵ログインに使う。サーバーはパスワードログインを無効にしているため、**失うと入れなくなる** |
| `~/.ssh/config.local` | Host定義 |
| `~/.config/dev/local.env` | MACアドレス等の機器固有値 |

### リセット後の手順

1. 退避した鍵を戻す。権限が重要。

   ```sh
   mkdir -p ~/.ssh && chmod 700 ~/.ssh
   cp <退避先>/<key> <退避先>/<key>.pub ~/.ssh/ && chmod 600 ~/.ssh/<key>
   ```

2. TailscaleとZedを入れ、同じアカウントでTailscaleにログインする。
3. [初回セットアップ](#初回セットアップ)の 2〜3 を行う (clone → `./install.sh macos` → `Include` 追記)。
4. 退避した `config.local` と `local.env` を元の場所に戻す。
5. `dev <target>` で動作を確認する。

### 秘密鍵まで失った場合

旧鍵ではどこにも入れない。新しい鍵を作って、3か所に登録し直す。

1. 新しい鍵を作る: `ssh-keygen -t ed25519`
2. **GitHub**: Settings の SSH keys に新しい公開鍵を登録する。
3. **サーバーとRaspberry Pi**: パスワード認証が無効なので `ssh-copy-id` は使えない。
   **コンソール** (モニターとキーボード) から、`~/.ssh/authorized_keys` に追記する。
4. **コンテナ**: [environments.md](environments.md) の `ssh_public_key` を新しい鍵に変え、
   コンテナを作り直す (中身が消えるので、先にGitHubへpushしておく)。

### 備えておくと楽になること

- 予備の鍵を1つ作り、GitHub・サーバー・Raspberry Piに登録しておく (Macを失っても入れる)。
- `config.local` と `local.env` のテンプレートを、パスワードマネージャーに残しておく。
