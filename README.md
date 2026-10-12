# 用 mieru 自建个人代理(单人自用版)

> 这份教程只教你给**自己一个人**搭一条线路:一台 VPS、一个账号、一个客户端。
> 不涉及多用户、面板、流量统计,也不建议把线路分享出去——共享的人越多,被识别的概率越高。

[mieru](https://github.com/enfein/mieru) 是一个开源的代理协议,服务端叫 **mita**,特点是流量没有固定特征、不依赖 TLS 证书和域名,搭建很简单。

整个过程大约 10 分钟:

1. 买一台海外 VPS
2. 运行一键脚本
3. 把输出的配置导入客户端
4. 连不上时按自检表排查

---

## 第一步:准备一台 VPS

| 项目 | 建议 |
|---|---|
| 系统 | **Debian 12** 或 Ubuntu 22.04 / 24.04(CentOS / Rocky 也支持) |
| 配置 | 1 核 512MB 内存就够一个人用 |
| 位置 | 日本、香港、新加坡、美国西海岸,离你越近延迟越低 |
| 架构 | x86_64 或 ARM64 |

买好后,用 SSH 以 root 身份登录(Windows 可以用系统自带的 PowerShell:`ssh root@你的IP`)。

## 第二步:一键安装

```bash
curl -fsSLO https://raw.githubusercontent.com/RiceBlack67/mieru-tutorial/main/install.sh
bash install.sh
```

脚本会做这些事,每一步都会在屏幕上显示:

- 从 mieru 官方 GitHub 下载最新版 mita 并校验 sha256
- 随机生成一个端口(11000-29901)、用户名和 24 位密码
- 开启 BBR(提升高延迟线路的速度)
- 检查服务器时间是否同步
- 如果系统防火墙(ufw / firewalld)开着,自动放行端口

运行结束会打印:

```
================ 客户端需要填的内容 ================
  协议      mieru
  服务器    203.0.113.10
  端口      23360
  传输      TCP
  用户名    uXEUEc2h
  密码      OzB30VpcObwjVh7Mhy95dzD0
  多路复用  低(MULTIPLEXING_LOW)
====================================================

分享链接(小火箭 / Hiddify 可直接导入):
  mierus://uXEUEc2h:OzB3...@203.0.113.10?profile=my-mieru&port=23360&protocol=TCP...

完整的 Clash Meta(mihomo)配置已保存在:/root/mieru-client.yaml
```

> ⚠️ **云服务商的安全组**:阿里云、腾讯云、AWS、Oracle、Google Cloud 等在网页控制台还有一层防火墙(叫「安全组」或「防火墙规则」),脚本改不到。请去控制台**放行脚本打印的那个 TCP 端口**,否则一定连不上。

以后想再看一次配置:`bash install.sh --show`

## 第三步:客户端

☠️ **最常见的坑:客户端不支持 mieru。** 原版 Clash、Clash for Windows、v2rayN(默认内核)都**不支持** mieru,导入后会全部超时或直接报错。请用下面这些:

| 平台 | 客户端 | 导入方式 |
|---|---|---|
| Windows / macOS / Linux | **Clash Verge Rev** | 导入 `mieru-client.yaml` 文件 |
| Android | **Clash Meta for Android** 或 **FlClash** | 导入 `mieru-client.yaml` 文件 |
| iOS / iPadOS | **Shadowrocket(小火箭)** | 复制 `mierus://` 链接,打开小火箭会提示添加 |
| iOS / Android / 桌面 | **Hiddify** | 复制 `mierus://` 链接,从剪贴板添加 |

它们共同点是:内核为 **mihomo(Clash Meta)** 或原生支持 mieru。

**怎么把 yaml 文件弄到电脑上**:

```bash
# 在你自己电脑上执行(不是 VPS 上)
scp root@你的VPS的IP:/root/mieru-client.yaml .
```

或者在 VPS 上 `cat /root/mieru-client.yaml`,复制全部内容,在电脑上新建一个 `.yaml` 文件粘进去。

这份配置已经写好了分流规则:国内网站直连,其他走代理。

## 第四步:连不上?按顺序查

| # | 检查什么 | 怎么查 / 怎么修 |
|---|---|---|
| 1 | **服务在不在跑** | VPS 上 `mita status`,应显示 `RUNNING`。不是的话 `systemctl restart mita` |
| 2 | **安全组放行了没** | 去云服务商控制台确认端口已放行(TCP) |
| 3 | **客户端内核对不对** | 见上一节,换成 mihomo 内核的客户端 |
| 4 | **两边时间准不准** | ☠️mieru 用时间做加密校验,**服务器或你的电脑/手机时间偏差超过 2 分钟,就会全部超时**(1~2 分钟时好时坏)。VPS 上 `timedatectl` 看 `System clock synchronized: yes`;手机/电脑打开「自动设置时间」 |
| 5 | **用户名密码有没有抄错** | 重新 `bash install.sh --show` 对一遍,注意别多复制空格 |
| 6 | **IP 是不是被封了** | 用 [itdog TCPing](https://www.itdog.cn/tcping/) 测 `你的IP:端口`:国内各地全红、而 VPS 上 `mita status` 正常,通常就是 IP 被墙了。换 IP(多数服务商可以付费换)或换机器 |

**关于测延迟**:

- 很多 VPS 屏蔽 ping(ICMP),「ping 不通」不等于「代理不能用」,判断能不能用直接打开网页试。
- 客户端里显示「超时」但网页能打开,一般是测速地址的问题,不用管。

## 常用命令

```bash
mita status                 # 查看运行状态
systemctl restart mita      # 重启服务
journalctl -u mita -n 50    # 看最近 50 行日志
bash install.sh --show      # 重新打印客户端配置
bash install.sh --uninstall # 完全卸载
```

**想换端口和密码**(比如怀疑端口被干扰了):先 `--uninstall` 再重新运行一次 `install.sh`,会生成全新的端口和密码,然后在客户端里重新导入。

**升级 mita**:同样先卸载再重装即可,脚本总是安装官方最新版。

## 常见问题

**Q:为什么选 mieru,不用 VLESS / Trojan / Hysteria?**
它们都很好。mieru 的优点是**不需要域名和证书**、流量没有固定特征、服务端只有一个程序,对新手来说要维护的东西最少。缺点是支持它的客户端比 VLESS 少,所以一定要用上面列出的客户端。

**Q:一台 VPS 能给几台设备用?**
同一个账号可以同时在手机和电脑上登录,自己的几台设备一起用没问题。

**Q:能分享给朋友吗?**
本教程只覆盖个人自用。多人共用一个 IP、流量大了以后更容易被识别和封锁,也可能违反 VPS 服务商的使用条款。

**Q:速度慢怎么办?**
大多数情况是 VPS 本身线路的问题(到国内的路由绕路、晚高峰拥堵)。可以换一个对国内线路有优化的 VPS(比如标注 CN2 GIA、CMI 的),或者换一个离你更近的机房。

**Q:安全吗?**
密码保存在 VPS 的 `/root/mieru-client.yaml` 和 `/etc/mieru-selfhost/`,只有 root 能读。不要把这个文件或 `mierus://` 链接发到群里或公开的地方。

---

本教程和脚本基于 mieru 官方文档整理,使用的全部是官方发布的安装包。mieru 项目地址:<https://github.com/enfein/mieru>
