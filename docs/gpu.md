# GPU (コンテナから使う)

サーバーのGPU (現在は GeForce RTX 3070 Ti, VRAM 8GB) を、**すべてのコンテナから、同時に、制限なく**使う。
プログラミングや、Kaggleのような機械学習の研究を想定している。

## 目次

- [仕組み](#仕組み)
- [導入 (1回だけ)](#導入-1回だけ)
- [コンテナで使う](#コンテナで使う)
- [GPUを増設したとき](#gpuを増設したとき)
- [Suspendとの関係](#suspendとの関係)
- [制約と注意](#制約と注意)
- [うまくいかないとき](#うまくいかないとき)

## 仕組み

```
サーバー(ホスト): NVIDIA公式ドライバ (カーネルモジュール, Debian non-free) を1つだけ導入
   │  Incusの gpu デバイスを、共通のprofile (dev-base) 経由で、全コンテナに渡す (ベンダーID 10de で指定)
   ├─ os-dev    /dev/nvidia* が見える → libcuda1 + nvidia-smi (ホストと同じ版) を導入
   ├─ lang-dev  同上
   └─ cpu-dev   同上
```

- コンテナは、ホストのカーネルを共有するので、**同じGPUを、全コンテナが同時に使える**。
- コンテナ内には、カーネルドライバを入れない。ホストと同じDebianのAPTから、**同じ版**の `libcuda1` と
  `nvidia-smi` を入れる。
- CUDAツールキットは不要。PyTorch / TensorFlow / JAX のpipパッケージは、CUDAのランタイムを同梱していて、
  `libcuda` だけで動く。

## 導入 (1回だけ)

順番に実行する。**手順2の再起動が必要。**

1. ホストにドライバを入れる (サーバー上で、一般ユーザーから)。

   ```sh
   cd ~/dotfile_infra/host && sudo ./setup.sh 35
   ```

   APTの `non-free` を有効にし、`nvidia-kernel-dkms` などを導入し、`nouveau` を無効にする。

2. **サーバーを再起動**し、確認する。

   ```sh
   sudo reboot
   # 再起動後
   nvidia-smi          # GPU名とドライバの版 (550.x) が出ればOK
   ```

3. OpenTofuで、全コンテナにGPUを渡す。

   ```sh
   cd ~/dotfile_infra && git pull && tofu plan && tofu apply
   ```

4. コンテナに、ライブラリを入れて、自己点検する。

   ```sh
   ./provision/run
   # [provision] gpu: GPU 0: NVIDIA GeForce RTX 3070 Ti ...
   # [provision] gpu: cuInit=0 devices=1
   ```

5. 自動Suspendを更新する (`GPUが計算中は寝ない` 判定が入る)。

   ```sh
   cd ~/dotfiles_server && git pull && sudo ./server/install-suspend.sh
   ```

6. **Suspend/Resumeを、サーバーの近くで試す** ([下記](#suspendとの関係))。

## コンテナで使う

```sh
nvidia-smi                                  # GPUが見えるか
python3 -m venv .venv && . .venv/bin/activate
pip install torch --index-url https://download.pytorch.org/whl/cu126   # CUDA 12.6版 (ホストのドライバ550はCUDA 12.xまで)
python -c "import torch; print(torch.cuda.is_available(), torch.cuda.get_device_name(0))"
```

- Kaggleのデータは、`kaggle` CLI (APIトークンは、各自のもの。Gitに入れない) で取得する。
- 複数のGPUがあるときは、`CUDA_VISIBLE_DEVICES=1 python train.py` で、使うGPUを選べる。
- あるコンテナだけGPUを外したいときは、`terraform.tfvars` の `dev_instances` で `gpu = false`。

## GPUを増設したとき

GPUは、PCIの番地ではなく、**ベンダーID**で渡している (`gpu_vendor_ids`、既定 `["10de"]` = NVIDIA)。

| 追加するGPU | 作業 |
| --- | --- |
| NVIDIAの2枚目以降 (同じドライバが対応する世代) | カードを挿して、サーバーを再起動し、**各コンテナを再起動**するだけ |
| AMD / Intel | `gpu_vendor_ids` に `1002` (AMD) / `8086` (Intel) を足して `tofu apply`。計算の環境 (ROCmなど) は別途 |
| 新しい世代のNVIDIA (RTX 50系など) | Debian 13のドライバは **550.163** で、対応しない可能性がある。NVIDIA公式リポジトリへの切り替えを検討 |

- 稼働中のコンテナには、増設したGPUが見えない。**コンテナを再起動**する。
- マザーボードのVGA (ASPEED, `1a03`) は、ベンダーが違うので、渡されない。
- ホストのドライバを更新したら、`./provision/run` で、コンテナの `libcuda1` も同じ版に揃える
  (版が違うと、`nvidia-smi` が `mismatch` で失敗し、プロビジョニングが警告する)。

## Suspendとの関係

- **GPUで計算している間は、寝ない。** 自動Suspendは、`nvidia-smi` のGPU使用率が閾値 (既定5%) 以上のとき
  「アクティブ」とする (`DEV_KEEP_AWAKE_GPU_UTIL`、複数枚は、どれか1つでよい)。VRAMを持っているだけで、
  使用率が0%の放置ノートブックは、寝るのを止めない。
- ホストでは、`NVreg_PreserveVideoMemoryAllocations=1` と `nvidia-suspend` サービスで、VRAMの内容を
  Suspend前に保存し、復帰後に戻す。
- **NVIDIAの公式ドライバとS3 Suspend/Resumeは、環境によって、復帰に失敗することがある。**
  失敗すると、電源の入れ直しが必要で、Wake-on-LANでは戻せない。ドライバを導入したあと、**サーバーの近くで**、
  次のとおり試す。

  ```sh
  sudo systemctl suspend          # 寝る (電源ボタンのLEDなどで確認)
  # Macから: dev os  (または ssh raspi 'dev-server-wake <MAC>')
  nvidia-smi                      # 復帰後もGPUが見えるか
  incus exec os-dev -- nvidia-smi # コンテナからも見えるか
  ```

  復帰しない場合は、電源ボタンで起こし、ドライバの設定を見直す。

## 制約と注意

- **GPUは1枚、VRAMは8GBを、全コンテナで分け合う。** VRAMの隔離は無い (民生用のGPUで、MIGも使えない)。
  1つのコンテナがVRAMを使い切ると、他のコンテナが、メモリ不足で落ちる。大きな作業は、1つずつ行う。
- 8GBは、小〜中規模の学習やコンペには足りるが、大きなモデルの学習には足りない。
- 計算が競合すると、全体が遅くなる (GPUは、時間で分けて使われる)。
- `docker` + NVIDIA Container Toolkit (Kaggleの公式イメージ) は、今は構築していない。必要になったら足す。

## うまくいかないとき

| 症状 | 確認 |
| --- | --- |
| ホストの `nvidia-smi` が失敗する | 再起動したか。`lsmod \| grep nvidia`。`nouveau` が残っていないか (`lsmod \| grep nouveau`) |
| コンテナに `/dev/nvidiactl` が無い | ホストのドライバが有効か。`tofu apply` したか。コンテナを再起動したか |
| コンテナの `nvidia-smi` が `mismatch` | `./provision/run` で、ホストと同じ版の `libcuda1` にする |
| `driver on your system is too old` | 既定の `pip install torch` はCUDA 13系。上の `--index-url .../whl/cu126` で入れ直す (ドライバ550はCUDA 12.x) |
| `torch.cuda.is_available()` が False | `nvidia-smi` が通るか。pipが、CPU版のtorchを入れていないか |
| 復帰後にGPUが見えない | サーバーを再起動する。`journalctl -u nvidia-resume` (sudo) を確認 |
