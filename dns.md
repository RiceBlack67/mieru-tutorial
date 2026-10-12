# Clash / mihomo 防 DNS 泄漏配置

节点域名用国内 DoH 直连解析，其他所有网站用境外 DoH 经代理解析。
本文同时说明怎么用 ping.pe 判断 IP 是否被墙，以及为什么 1.1.1.1 在墙内连不上。

> 进阶内容，可选。本教程 `install.sh` 生成的配置只管翻出去，DNS 走国内，能正常用。介意 DNS 泄漏的话，再按下面改。

---

## 1. 用 ping.pe 判断 IP 是否被墙

在 [tcp.ping.pe](https://tcp.ping.pe/) 测 `你的IP:端口`，只看中国区的结果：

| 结果 | 判断 |
|---|---|
| 只有 Tencent 几行红，电信 / 联通 / 移动 / 阿里云全绿 | ✅ 没被墙 |
| 电信 / 联通 / 移动 / 阿里云一起红 | ❌ 被墙了 |

我们拿两台不同商家的机器（DMIT、AWS）测 TCP 端口，结果都是只有腾讯红，其他全绿，所以腾讯红跟 IP 本身无关。
想看被墙是什么样子，可以测 `1.1.1.1:443`：中国区所有探测点一起红，海外全绿。

## 2. 为什么 1.1.1.1 / 8.8.8.8 在墙内连不上

1.1.1.1 和 8.8.8.8 的 443 / 853 端口提供加密 DNS（DoH / DoT）。
墙的主要手段之一是 DNS 污染，前提是查询是明文的。加密 DNS 墙看不见也改不了，所以整个被封。
普通 53 端口的明文 DNS 能被污染，反而一般不封。

## 3. 一个常见的坑：死循环

节点域名要在代理连上**之前**先解析。如果节点域名交给 1.1.1.1 / 8.8.8.8 的 DoH 去查：

```
连不上 DNS → 解析不出节点 → 代理起不来 → 还是连不上 DNS
```

结果就是所有节点超时。

## 4. 配置：DNS 分两路

```yaml
dns:
  enable: true
  ipv6: false
  enhanced-mode: fake-ip
  fake-ip-range: 198.18.0.1/16
  respect-rules: true
  default-nameserver:
    - 223.5.5.5
    - 119.29.29.29
  # 节点域名：国内能连的加密 DNS，直连解析
  proxy-server-nameserver:
    - https://dns.alidns.com/dns-query
    - https://doh.pub/dns-query
  # 其他所有网站：境外 DoH，经代理隧道出境去查
  nameserver:
    - https://1.1.1.1/dns-query
    - https://8.8.8.8/dns-query
```

| 要解析的 | 用哪个 DNS | 怎么连过去 |
|---|---|---|
| 节点域名 | `proxy-server-nameserver`（alidns / doh.pub） | 直连。这时代理还没起来，只能用墙内能连的 |
| 其他所有网站 | `nameserver`（1.1.1.1 / 8.8.8.8） | 走代理，从海外 VPS 发出 |

### 关键是 `respect-rules: true`

开了它，DNS 请求本身也按规则走代理，是从海外 VPS 发出去的，那里能连上 1.1.1.1。

- 国内 DNS 只看到你的节点域名，看不到你访问了哪些网站
- 境外 DoH 查出来的地址是干净的，不会被污染

需要 mihomo 1.18.6 及以上（稳妥用 1.19+）。
电脑端建议开 TUN 模式，只开系统代理的话，部分程序不走代理。

## 5. 为什么不直接用国内 DNS？

fake-ip 模式下，被代理的网站其实是 VPS 自己去解析和连接的，所以国内 DNS 污染一般**不会导致连不上**。问题在于谁知道你查了什么：

1. **国内 DNS 会留下记录**：你访问的每个境外网站，域名都会出现在国内解析器的日志里。代理把流量藏住了，DNS 却把「你去了哪」交了出去，这就是 DNS 泄漏。
2. **泄漏检测一测就露馅**：IP 显示在美国，DNS 却显示在中国，一眼就看出在用代理。
3. **按 IP 判断的规则可能分错**：GEOIP 这类规则要先解析出 IP，拿着被污染的假地址去判断，可能分错流。

代价：

- 境外网站第一次打开要先绕代理查 DNS，会慢一点（之后有缓存）
- 国内网站也用境外 DNS 的话，可能被分到不是最近的 CDN 节点，所以分流时把国内网站单独交给国内 DoH（见下一节）

## 6. 分流版

用 `nameserver-policy` 把国内网站交给国内 DoH，其他网站照旧走境外 DoH + 代理：

```yaml
dns:
  nameserver-policy:
    'geosite:geolocation-!cn':
      - https://1.1.1.1/dns-query
      - https://8.8.8.8/dns-query
    'geosite:cn':
      - https://doh.pub/dns-query
      - https://dns.alidns.com/dns-query

rules:
  - GEOSITE,category-ip-geo-detect,PROXY
  - GEOSITE,geolocation-!cn,PROXY
  - GEOSITE,cn,DIRECT
  - GEOIP,CN,DIRECT
  - MATCH,PROXY
```

> ⚠️ `geosite:cn` 里混了一些境外网站，比如 browserleaks.com，会被当成国内网站直连，泄漏检测会显示你的真实运营商。
> 所以先用 `geolocation-!cn` 和 `category-ip-geo-detect`（检测类网站）把境外网站钉死走代理，再判断国内。
> `nameserver-policy` 按书写顺序匹配，顺序不能反。

## 7. 检测有没有泄漏

- [browserleaks.com/dns](https://browserleaks.com/dns)
- [ipleak.net](https://ipleak.net)
- [dnsleaktest.com](https://www.dnsleaktest.com)（点 Extended test）

看 DNS 服务器那一栏：

- ✅ 显示 Cloudflare / Google，或者 VPS 所在的国家 → 没泄漏
- ❌ 出现中国电信、联通、移动，或者阿里、腾讯 → 泄漏了

## 总结

1. ping.pe 只看电信、联通、移动、阿里云，腾讯红不用管
2. 1.1.1.1 / 8.8.8.8 的加密 DNS 在墙内直连不通
3. 节点域名用国内 DoH 直连查，其他网站用境外 DoH 走代理查
