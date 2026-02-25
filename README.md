# IPv4 over SRv6 検証環境 構成ドキュメント

## 概要

libvirt上に6台のVM（Debian）を構築し、IPv4 over SRv6を実証する検証環境。
vm01 ↔ vm05間のIPv4通信を、SRv6バックボーン（vm02 - vm03 - vm04）を経由して転送する。

## ネットワークトポロジ

```
vm01 ──(nw1/IPv4)── vm02 ──(nw2/IPv6)── vm03 ──(nw3/IPv6)── vm04 ──(nw4/IPv4)── vm05
                                           │
                                        (nw5/IPv6)
                                           │
                                          vm06
```

## VM一覧と役割

| VM   | 役割                         | 接続ネットワーク   |
|------|-----------------------------|--------------------|
| vm01 | IPv4エンドポイント（送信元）  | nw1                |
| vm02 | SRv6 Ingress/Egress ノード  | nw1, nw2           |
| vm03 | SRv6 Transit ノード          | nw2, nw3, nw5      |
| vm04 | SRv6 Ingress/Egress ノード  | nw3, nw4           |
| vm05 | IPv4エンドポイント（宛先）    | nw4                |
| vm06 | IPv6エンドポイント            | nw5                |

## ネットワークセグメント

| ネットワーク | プロトコル | サブネット       | 用途                    |
|-------------|-----------|-----------------|------------------------|
| nw1         | IPv4      | 10.1.0.0/24     | IPv4アクセスセグメント    |
| nw2         | IPv6      | fd00:2::/64     | SRv6バックボーン         |
| nw3         | IPv6      | fd00:3::/64     | SRv6バックボーン         |
| nw4         | IPv4      | 10.4.0.0/24     | IPv4アクセスセグメント    |
| nw5         | IPv6      | fd00:5::/64     | IPv6接続（vm06用）       |

> 管理用ネットワーク `default`（192.168.122.0/24）はTerraformが自動でDHCP割当。各VMのenp1s0に接続。

## IPアドレス割当

### インターフェースマッピング

各VMのNICは以下の順序で割り当てられる（q35 + virtio）:

| NIC      | 用途                                |
|----------|-------------------------------------|
| enp1s0   | 管理用（default, DHCP）             |
| enp2s0   | 1つ目の追加ネットワーク              |
| enp3s0   | 2つ目の追加ネットワーク              |
| enp4s0   | 3つ目の追加ネットワーク              |

### 各VMのアドレス

| VM   | インターフェース | ネットワーク | アドレス         |
|------|-----------------|-------------|-----------------|
| vm01 | enp2s0          | nw1         | 10.1.0.1/24     |
| vm02 | enp2s0          | nw1         | 10.1.0.2/24     |
| vm02 | enp3s0          | nw2         | fd00:2::2/64    |
| vm03 | enp2s0          | nw2         | fd00:2::3/64    |
| vm03 | enp3s0          | nw3         | fd00:3::3/64    |
| vm03 | enp4s0          | nw5         | fd00:5::3/64    |
| vm04 | enp2s0          | nw3         | fd00:3::4/64    |
| vm04 | enp3s0          | nw4         | 10.4.0.4/24     |
| vm05 | enp2s0          | nw4         | 10.4.0.5/24     |
| vm06 | enp2s0          | nw5         | fd00:5::6/64    |

## SRv6設計

### SID体系

- Locator プレフィクス: `fd00:a:<node>::/48`
  - vm02: `fd00:a:2::/48`
  - vm04: `fd00:a:4::/48`

### Local SID

| ノード | SID              | Action   | パラメータ                |
|--------|-----------------|----------|--------------------------|
| vm02   | fd00:a:2::d4    | End.DX4  | nh4 10.1.0.1 dev enp2s0  |
| vm04   | fd00:a:4::d4    | End.DX4  | nh4 10.4.0.5 dev enp3s0  |

### SRv6 H.Encaps ルート

| ノード | 対象トラフィック | SRH Segments     | 出力IF  |
|--------|-----------------|------------------|---------|
| vm02   | 10.4.0.0/24     | fd00:a:4::d4     | enp3s0  |
| vm04   | 10.1.0.0/24     | fd00:a:2::d4     | enp2s0  |

### データパス

**往路（vm01 → vm05）:**

```
vm01 (10.1.0.1) → [IPv4: dst 10.4.0.5]
  → vm02 enp2s0 受信
  → H.Encaps: IPv6 src=fd00:2::2, dst=fd00:a:4::d4, SRH=[fd00:a:4::d4]
  → vm02 enp3s0 送出
  → vm03 enp2s0 受信 (transit forwarding)
  → vm03 enp3s0 送出
  → vm04 enp2s0 受信
  → End.DX4: デカプセレーション, nh4=10.4.0.5
  → vm04 enp3s0 送出
  → vm05 (10.4.0.5) 受信
```

**復路（vm05 → vm01）:**

```
vm05 (10.4.0.5) → [IPv4: dst 10.1.0.1]
  → vm04 enp3s0 受信
  → H.Encaps: IPv6 src=fd00:3::4, dst=fd00:a:2::d4, SRH=[fd00:a:2::d4]
  → vm04 enp2s0 送出
  → vm03 enp3s0 受信 (transit forwarding)
  → vm03 enp2s0 送出
  → vm02 enp3s0 受信
  → End.DX4: デカプセレーション, nh4=10.1.0.1
  → vm02 enp2s0 送出
  → vm01 (10.1.0.1) 受信
```

## スタティックルート

### IPv4ルート

| VM   | 宛先           | NextHop    | IF      |
|------|---------------|------------|---------|
| vm01 | 10.4.0.0/24   | 10.1.0.2   | enp2s0  |
| vm05 | 10.1.0.0/24   | 10.4.0.4   | enp2s0  |

### IPv6ルート（SRv6 Locator到達性）

| VM   | 宛先              | NextHop      | IF      |
|------|-------------------|-------------|---------|
| vm02 | fd00:a:4::/48     | fd00:2::3   | enp3s0  |
| vm03 | fd00:a:4::/48     | fd00:3::4   | enp3s0  |
| vm03 | fd00:a:2::/48     | fd00:2::2   | enp2s0  |
| vm04 | fd00:a:2::/48     | fd00:3::3   | enp2s0  |

## カーネルパラメータ (sysctl)

| VM   | パラメータ                           | 値 |
|------|--------------------------------------|---|
| vm02 | net.ipv4.ip_forward                  | 1 |
| vm02 | net.ipv6.conf.all.forwarding         | 1 |
| vm02 | net.ipv6.conf.all.seg6_enabled       | 1 |
| vm02 | net.ipv6.conf.enp3s0.seg6_enabled    | 1 |
| vm03 | net.ipv6.conf.all.forwarding         | 1 |
| vm03 | net.ipv6.conf.all.seg6_enabled       | 1 |
| vm03 | net.ipv6.conf.enp2s0.seg6_enabled    | 1 |
| vm03 | net.ipv6.conf.enp3s0.seg6_enabled    | 1 |
| vm04 | net.ipv4.ip_forward                  | 1 |
| vm04 | net.ipv6.conf.all.forwarding         | 1 |
| vm04 | net.ipv6.conf.all.seg6_enabled       | 1 |
| vm04 | net.ipv6.conf.enp2s0.seg6_enabled    | 1 |

## ファイル構成

```
.
├── ansible.cfg          # Ansible設定（inventory, ssh_config参照）
├── inventory.ini        # ホスト一覧 [vms]
├── ssh_config           # VM別SSH接続設定（管理IP, 鍵）
├── site.yml             # メインPlaybook
├── host_vars/           # VM別変数
│   ├── vm01.yml
│   ├── vm02.yml
│   ├── vm03.yml
│   ├── vm04.yml
│   ├── vm05.yml
│   └── vm06.yml
├── resources.tf         # Terraform定義（VM, ネットワーク, ボリューム）
├── user.yaml            # cloud-init設定（SSH鍵注入）
├── id / id.pub          # SSH鍵ペア
└── scripts/
    ├── gen-conns.sh     # terraform output → ssh_config, inventory.ini 生成
    ├── copy.sh
    └── download.sh
```

## Playbook構成 (site.yml)

| Play | 名前                                                | 内容                                  |
|------|-----------------------------------------------------|---------------------------------------|
| 1    | Configure static IP addresses                       | NIC link up + IPアドレス付与           |
| 2    | Configure kernel parameters for forwarding and SRv6 | sysctl設定（ランタイム）               |
| 3    | Configure static routes                             | IPv4/IPv6スタティックルート            |
| 4    | Configure SRv6 encapsulation and local SIDs         | H.Encaps + End.DX4設定               |

## 操作手順

### 1. インフラ構築（Terraform）

```bash
terraform apply
```

### 2. 接続情報生成

```bash
bash scripts/gen-conns.sh
```

### 3. ネットワーク設定適用（Ansible）

```bash
ansible-playbook site.yml
```

### 4. 疎通確認

```bash
# vm01からvm05へping（IPv4 over SRv6）
ssh -F ssh_config vm01 ping -c 3 10.4.0.5

# vm05からvm01へping（復路）
ssh -F ssh_config vm05 ping -c 3 10.1.0.1
```
