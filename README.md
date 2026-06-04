# kepinstall
kep 一键安装脚本

#### 集成 kep-edge+kep-webui+caddy 三合一 一键安装脚本

### 使用方法

```bash
wget https://raw.githubusercontent.com/ubtolan/kepinstall/refs/heads/main/kepinstall.sh
bash kepinstall.sh
```

输入相关信息即可。

### 注意事项

1.caddy默认是自签名，需要替换默认的ca.crt，ca.key为自己的证书

2.“**绑定域名:**”这个输入的是txt验证域名，而非webui访问域名

3.脚本实现了三合一，通过caddy路径反代，从而实现webui与edge共用一个https端口
