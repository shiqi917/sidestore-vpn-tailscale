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
device:P  →  NODE_ADDR:Q       (SideStore 撥 NODE_ADDR)
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

1. ```sh
   cp .env.example .env      # 填入 TS_AUTHKEY
   docker compose up -d --build
   ```
   容器會自己抓本節點的 Tailscale IP
   (`docker logs sidestore-vpn | grep "node address"`),
   這就是**反射位址** `NODE_ADDR`。不用 +1,也不用到管理頁改機器 IP。

2. (建議)在路由器把 **UDP 41642** 轉發到跑 Docker 的主機,
   其他節點才能直連,不用繞 DERP 中繼。用 `tailscale ping <NODE_ADDR>`
   確認:應顯示 `via <公網IP>:41642`,而不是 `via DERP`。

3. iOS 裝置上:SideStore → Settings → **Connection Config** →
   **Use Local VPN 關掉**(Remote Endpoint 模式)→ **Device IP** 填
   `NODE_ADDR`,RemotePair Port 留空 → Confirm。

4. 驗證:iOS 裝置上(Wi-Fi + Tailscale 開)SideStore → Settings →
   Health Check:Device Reachability 綠燈。開刷。

> **為什麼用 Remote Endpoint,不用 Use Local VPN?** SideStore 0.7.0
> (LiveContainer 3.8.10 nightly)的 Local VPN 模式透過 Tailscale 一直連不到
> 裝置(Health Check:`NoDevice … DeviceEndpointNotInitialized`),就算已經
> 直連也一樣;同一個 IP 改用 Remote Endpoint 模式則馬上通。用 Remote
> Endpoint 也代表反射器不必再站在「裝置 IP + 1」。路徑慢或走中繼時,
> 把 Developer Options → Device (TCP) Probe Timeout 調到 2000 ms 也有幫助。
>
> 還是想用 Local VPN 模式?在 `.env` 設 `NODE_ADDR` = 裝置 Tailscale IP + 1,
> 並到[管理頁](https://login.tailscale.com/admin/machines)把本機 IPv4 改成同一個值。

## 裝置 IP 變了 / 多台裝置

反射器只是把封包原路送回發送者,不在乎裝置的 IP:IP 變了不用改任何東西。
多台 iOS 裝置應該可以共用同一個反射器(各自把 Device IP 填 `NODE_ADDR`)——
尚未實測。

## 致謝

- [xddxdd/sidestore-vpn](https://github.com/xddxdd/sidestore-vpn) ——
  本專案 fork 自的原始反射器(公有領域 / Unlicense)
- [SideStore](https://github.com/SideStore/SideStore) 與
  [minimuxer](https://github.com/SideStore/minimuxer)
