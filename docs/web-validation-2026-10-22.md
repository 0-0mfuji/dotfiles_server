# web-dev / igakutteru の同期・検証記録 (2026-10-22)

Mac の `/Users/mfujimak/home/igakutteru` を基準に、`web-dev:~/src/igakutteru` を照合・同期した。
コード・必要データの転送は完了。テストは全成功ではなく、以下の不整合が残る。

## コードと退避先

| 項目 | 内容 |
| --- | --- |
| Mac の基準 | `staging`, `eda878867604b23e74ba8944ba127cc8b7c57ba6` |
| 同期前の web-dev | `main`, `2d1b1b28daf5971eaa2af0bffb3317be2097aa5b` |
| 同期後の web-dev | `codex/mac-sync-20261022`, Mac と同じコミット |
| 同期前のコードの退避 | web-dev の `codex/pre-mac-sync-20261022` ブランチ |
| 上書きデータの退避 | web-dev の `~/migration-backups/igakutteru-20261022/pre-sync-data.tar.zst` |

同期前は双方に固有コミットがあり (Mac側77、web-dev側2)、ツリー差分は2,849ファイル。
Git bundleでMac側のコミットと全パイプライン・テストを転送し、新しい作業ブランチに展開した。
GitHubへのpushやデプロイは行っていない。`dev web igakutteru` の接続先ディレクトリは従来どおり。

Mac の `data/ontology.duckdb` は `skip-worktree` が設定され、実ファイルがLFSポインタと異なっていた。
Macの実ファイルを再現したため、web-devではこの1ファイルが変更として見える。
これは同期漏れではない。Macの実ファイルはSHA-256 `3f596a2ce8a6631f8ced4e3ba20d58de874a9e965fa31680cd8fbcdcd1707046`、
Git LFSに記録された版は `cc8eacef22a4b0a925328fd56f716c1249535a67830839f2109e29848924cec4`。

## データ照合

以下はファイル内容のSHA-256とサイズで照合した。画像リンクはLinuxで使える相対リンクを維持した。

| 対象 | 件数 | 結果 |
| --- | ---: | --- |
| `data/` 全体 | 70,563 | 一致 |
| `data/question/` (上記の内数) | 350 | 一致 |
| `data/images/` (上記の内数) | 3,465 | 一致 |
| `data/drug_pipeline_runs/` (上記の内数) | 11,870 | 一致 |
| `data/ontology_raw/` (上記の内数) | 28 | 一致 |
| `questions/` | 8,050 | 一致 |
| `taxonomy/` | 3 | 一致 |
| `pipeline/.dict-cache/` | 8 | 一致 |
| `web/public/` | 204 | 一致 |

全体では78,828ファイルが一致。`web/public/spike/igakutteru-spike.db` は全体照合で唯一不足していたため、
最後に追加転送し、個別にSHA-256の一致を確認した。

今回の差分転送は、PDF163件の追加、PDF1件の更新、ontology DB、辞書8件、検索スパイクDBの計174ファイル、
圧縮前約2.7GB。一致済みの大きなデータは再送しなかった。以前から実行中だった別の転送は停止せず、
今回の転送と既存転送の終了後に全体を照合した。

秘密ファイルは既存の `.env` / `apps/worker/.dev.vars` を維持し、内容は表示していない。
Macの依存環境・ビルド成果物・過去のバックアップは追加転送せず、Linux側で依存を整えた。

## 実行結果

Macと同じコミットに同期した後の結果。Pythonは不足依存と拡張を補った後に再実行した最終結果を記載する。

| 検証 | コマンド | 結果 |
| --- | --- | --- |
| JS依存 | `pnpm install --frozen-lockfile` | 成功 |
| Worker | `pnpm --filter @igakutteru/worker test` | 622成功、1スキップ |
| Web | `pnpm --filter web test` | 917成功、スキップなし (実PDF統合テスト2件を含む) |
| Python | `pipeline/.venv/bin/python3 -m pytest pipeline --runslow -q` | 645成功、33失敗、スキップなし |
| 設計スクリプト | `pnpm design:test` | 9成功 |
| 補助スクリプト | `node --test scripts/agent-staging-preflight.test.mjs` | 5成功 |
| lint | `pnpm --filter web lint` | 452エラー、24警告で失敗 |
| 設計lint | `pnpm lint:design` | 成功 (ルールのテスト5件も成功) |
| Storybook命名 | `pnpm lint:storybook` | 命名エラー29件で失敗 |
| 本番ビルド | `pnpm build:web` | 成功 (大きいchunkの警告あり) |
| ナビゲーション | `pnpm --filter web test:navigation` 相当 | 6成功 |
| 画面比較 | `pnpm --filter web test:visual` 相当 | 13成功、11失敗 |
| 実PDF OCR | `pnpm --filter web test:question-import-real` 相当 | 1成功 |
| Storybookビルド | `pnpm storybook:build` | export不足2件で失敗 |
| Storybook画面比較 | `pnpm --filter web test:design` のブラウザ段階 | 前提のStorybookビルド失敗により未実行 |

Playwrightは`--workers=2 --reporter=line`を付け、出力先を検証ログ用の一時ディレクトリに分けた。
既存Viteサーバーを利用した。Workerを起動した状態のアプリ全体の連携動作や実API課金を伴う処理は検証していない。
Workerのスキップ1件は、実GitHubにコミットを作成・更新・削除するE2Eで、専用トークンとテストブランチが未指定のため。

## 残る問題と環境の補完

- `expected.db` は3,799問、実DBは8,050問で、スナップショット比較31件が失敗する。
  両方のDBはそれぞれMacと一致しており、転送破損ではない。基準を実DBで上書きしてテストを通す操作はしていない。
- Modal用の2テストは `KNOWLEDGE_EMBEDDING_REVISION` が未設定で失敗する。
  テストfixtureが必須のモデルrevisionを準備していない。任意の値を設定して成功扱いにはしていない。
- Webの画面比較にはスクリーンショット差分、`問題` と `問題セット` に同時一致するlocator、
  表示待ちタイムアウト、APIへの502応答がある。Viteの`/api`プロキシ先はローカルWorker (`:8787`)。
  すべてをLinuxのフォント差として扱うことはできない。
- Storybookは `.storybook/mocks/clinicalNotesApi.ts` の `ClinicalNoteOfflineError`、
  `.storybook/mocks/queries.ts` の `getTaxonomySuggestions` が未exportでビルドできない。
- `pyarrow` がrequirementsに未記載で、最新Pythonテストの収集時に不足した。環境に追加済み。
- DuckDB VSS拡張をインストールし、`LOAD vss` の成功を確認した。
- パイプライン本体は `mistralai.client.models` を使うためSDK 2系が必要。
  `requirements-ocr-worker.txt` の `mistralai<2` と不整合がある。
  ワーカー用制約も一度検証したが、本体のOCRテストが壊れるため、本体環境は2系へ戻した。
  ワーカーrequirementsと現在のコードの整合は別途修正が必要。
- GPUは `torch 2.14.1+cu126`、`torch.cuda.is_available() == True` を確認。

## 記録と再実行

web-dev のログ・Playwright traceは `/tmp/igakutteru-synced.LOEzLl/`。
Macにも `/tmp/igakutteru-validation-20261022/` にログを保存した。一時領域なので永続保存が必要なら別途退避する。
旧コミットの初回検証ログはweb-devの `/tmp/igakutteru-audit.dawOUL/` にある。
最終結果は旧コミットの462件/673件という件数と区別すること。

再現手順と全検証コマンドは [web.md](web.md) に反映した。
長いテスト・転送は `systemd-inhibit`、Macからの転送中は `caffeinate` も利用してスリープを抑止した。

## Mac側との実測比較 (同日追記)

主要テスト・lint・ビルドの成功/失敗は一致した。画面比較の全件実行のみMac側に1件多く失敗があったが、
その1件を条件を揃えて単独で3回ずつ実行すると両側とも成功した。全件実行の結果は同一とはしていない。

Macの既存 `node_modules` と `pipeline/.venv` を利用し、依存パッケージを入れ替えずに同じ検証を実行した。
両側のHEADは `eda878867604b23e74ba8944ba127cc8b7c57ba6`。
Macの5173番はweb-devへのSSHトンネルだったため、そのまま利用せず、
比較用Playwright設定を `/tmp/igakutteru-mac-validation-20261022/` に作成してMacのViteを5273番で起動した。
テスト本体・基準画像・アサーションは変更していない。

| 環境 | Mac | web-dev |
| --- | --- | --- |
| Node | 26.5.0 | 22.23.3 |
| Python | 3.12.14 | 3.12.15 |
| DuckDB (Python) | 1.5.3 | 1.5.6 |
| torch | 2.12.0 | 2.14.1+cu126 |
| Mistral SDK | 2.4.9 | 2.10.1 |
| pyarrow | 25.0.1 | 26.0.0 |

| 検証 | Mac | web-dev | 照合 |
| --- | --- | --- | --- |
| Web | 917成功 | 917成功 | 一致 |
| Worker | 622成功、1スキップ | 622成功、1スキップ | 一致 |
| Python (`--runslow`) | 645成功、33失敗 | 645成功、33失敗 | 失敗した33件のテスト名も一致 |
| 設計スクリプト | 9成功 | 9成功 | 一致 |
| 補助スクリプト | 5成功 | 5成功 | 一致 |
| lint | 452エラー、24警告 | 452エラー、24警告 | 476件の診断内容も一致 |
| 設計lint | 成功、ルールテスト5成功 | 同左 | 一致 |
| Storybook命名 | 29エラー | 29エラー | エラー内容も一致 |
| 本番ビルド | 成功 | 成功 | 一致 |
| ナビゲーション | 6成功 | 6成功 | 一致 |
| 画面比較 | 12成功、12失敗 | 13成功、11失敗 | 共通の失敗11件とMacのみの失敗1件 |
| 実PDF OCR | 1成功 | 1成功 | 一致 |
| Storybookビルド | export不足2件で失敗 | 同左 | 同じexportが不足 |
| Storybook画面比較 | 前提ビルド失敗で未実行 | 同左 | 両側とも未実行 |

Pythonの33失敗は、両側で `test_db_snapshot.py` の31件と、
`test_knowledge_question_linker.py` / `test_knowledge_sentence_linker.py` の各1件。
失敗名の集合をログから抽出して一致を確認した。警告数はMacが10、web-devが8で異なる。
lintはJSON形式で両側の結果を取得し、チェックアウト先の絶対パスを正規化した上で、
ファイル名・行列・ルール・重大度・メッセージの476件すべてが一致することを確認した。

画面比較の共通失敗11件は、テスト名の集合として一致した (通信エラーのHTTPステータスや画像の差分ピクセル数は異なる)。
Macのみ失敗したのは `web/tests/visual/landing.spec.ts:69` の
`device mock reserves layout space and stays decorative across breakpoints`。
`[data-landing-device-mock]` の存在待ちが5秒でタイムアウトした。
両側とも新しいViteを5283番に起動し、同じテストを `--workers=1 --repeat-each=3` で単独実行したところ、
Macは3/3成功、web-devも3/3成功だった。実行負荷やタイミングによる不安定さが疑われるが、原因は未確定。
失敗の除外や基準画像の更新は行っていない。

Macの初回実行中は空き容量不足 (`ENOSPC`) が発生したため、初回中断は比較から除外した。
今回作成した一時ファイルと失敗ビルドの生成物を整理し、Workerは1並列・ログ抑制、
Pythonは `--capture=sys --tb=short --show-capture=no` と専用の一時ディレクトリで再実行した。
これらはログ・並列数の変更であり、テスト対象やアサーションの変更ではない。
既存のユーザーファイルや依存パッケージは容量確保のために削除していない。

Macの比較ログ、結果JSON、Playwright traceは `/tmp/igakutteru-mac-validation-20261022/` に保存した。
