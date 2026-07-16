# sidestore-vpn-tailscale

[English](README.md) | 繁體中文

透過 [Tailscale](https://tailscale.com) 刷新 [SideStore](https://sidestore.io)
(nightly、新版 `idevice` 架構)——不用 LocalDevVPN、不用切換 VPN,
Tailscale 常開,人在任何 Wi-Fi 上都能直接刷新。

基於 [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn),
適配新版 SideStore 架構(2026+ nightly / 0.6.3+)。

## 為什麼舊方案失效了

舊版 SideStore 的 minimuxer 寫死撥 `10.7.0.1`,所以反射器只要廣播
`10.7.0.1/32` 路由就行。新版(Swift 重寫的 minimuxer)改成
**從當前 VPN 介面推導撥號目標:`utun 介面 IP + 1`**
(Tailscale 建立的正是 /32 點對點 utun)。開著 Tailscale 時,
SideStore 撥的是「你裝置的 Tailscale IP + 1」,`10.7.0.1` 再也不會被用到。

過程中還挖出兩個坑:

- Tailscale **不會發布落在自家 CGNAT 範圍(100.64.0.0/10)內的 subnet
  route**——管理頁可以核准,但其他節點永遠收不到(靜默過濾)。
  所以反射位址不能用 subnet route 提供,改成**把本節點自身的 Tailscale IP
  設成反射位址**,再用 NAT 把流量導進反射器 TUN。
- **`--snat-subnet-routes=false` 是必要的**。Tailscale 預設的 MASQUERADE
  會在反射器看到封包前就改寫來源位址,反射出去的流量會彈回容器自己。

## 運作原理

```
device:P  →  NODE_ADDR:Q       (minimuxer 撥 <裝置IP>+1)
   DNAT   →  10.7.0.1:Q        (導進反射器 TUN)
  反射    →  src/dst 對調      (58 行 Rust)
   SNAT   →  NODE_ADDR:P  →  device:Q   (回到裝置自己的
                                          lockdownd/RSD 服務)
```

iOS 裝置最終是在跟自己對話——這正是 SideStore 安裝/刷新所需要的。

## 需求

- tailnet 裡一台能跑 Docker 的 Linux 機器(NAS、伺服器皆可)
- SideStore nightly + RPPairing 配對檔(用 iloader 產生)
- **iOS 裝置必須連著某個 Wi-Fi**。iOS 只在連上 Wi-Fi 時才開放
  lockdownd/RSD 服務;純行動網路刷新在系統層就不可能——用這個工具、
  用 LocalDevVPN、用任何方案都一樣。(實測驗證:62078/49152 兩個
  port 在行動網路下關閉、連上 Wi-Fi 才開。)

## 安裝

1. 查你 iOS 裝置的 Tailscale IP(Tailscale app 裡看),反射位址 =
   該 IP **+ 1**:例如 `100.101.102.103` → `100.101.102.104`

2. ```sh
   cp .env.example .env      # 填入 TS_AUTHKEY 和 NODE_ADDR
   docker compose up -d --build
   ```

3. 到 [Tailscale 管理頁](https://login.tailscale.com/admin/machines),
   找到新出現的 `sidestore-vpn` 機器 → **Edit machine IPv4 address** →
   改成跟 `NODE_ADDR` 一樣的值

4. 驗證:任一 tailnet 裝置 `ping <NODE_ADDR>` 應有回應。
   iOS 裝置上(Wi-Fi + Tailscale 開)SideStore → Settings →
   Health Check:Tunnel Peer IP 應為 `NODE_ADDR`、
   Device Reachability 綠燈。開刷。

## 裝置的 Tailscale IP 變了怎麼辦

反射位址是從裝置 IP 推導的,兩處要同步改:
`.env` 的 `NODE_ADDR` **加上**管理頁的機器 IPv4,
然後 `docker compose up -d --build`。

多台 iOS 裝置就各跑一個反射器(一台一個 `<IP>+1` 節點)。

## 致謝

- [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn) ——
  本專案 fork 自的原始反射器(公有領域 / Unlicense)
- [SideStore](https://github.com/SideStore/SideStore) 與
  [minimuxer](https://github.com/SideStore/minimuxer)
