# 使い方 (`dev` コマンド)

```sh
dev os        # config/projects.conf の "os" targetを開く
dev cpu
dev flutter
```

## 目次

- [`dev` がすること](#dev-がすること)
- [projects.conf](#projectsconf)
- [ソースコードの置き場所](#ソースコードの置き場所)

## `dev` がすること

1. Development Serverに接続できなければ、Raspberry Pi経由でWake-on-LAN
2. SSHが通るまで待つ (`DEV_SERVER_WAIT_TIMEOUT` 秒、既定180)
3. `instance` が設定されていれば、停止中のIncusコンテナを起動
4. `repo` が設定されていて、コンテナ内に `path` が無ければ `git clone`
   (Macのsshエージェントを転送して認証する。privateでもOK。秘密鍵はコンテナに置かない)
5. ZedのRemote Developmentで `path` を開く

## projects.conf

[config/projects.conf](../config/projects.conf) を編集する。1行が1つのtarget。

```
# target  host      path            instance   repo
os        os-dev    ~/src/os        os-dev     git@github.com:you/my-os.git
```

| 列 | 内容 |
| --- | --- |
| `target` | `dev <target>` の名前 |
| `host` | `~/.ssh/config.local` で定義したSSH Host名 |
| `path` | コンテナ内のプロジェクトパス |
| `instance` | Incusコンテナ名。`-` で無指定 |
| `repo` | GitHubのクローンURL。`-` で無指定 |

1つのtargetに設定できる `repo` は1つ。複数ある場合は、別のtargetとして行を足す。

## ソースコードの置き場所

**ソースコードはすべてコンテナ内の `path` に置き、Macには置かない。** ZedのUIと入力だけが
Macで動き、ファイル・Git・ターミナル・ビルドはコンテナ内で動く。

コンテナを作り直すと中身は消える。重要な変更は必ずGitHubへpushする。
