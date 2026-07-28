#!/usr/bin/env bash

set -e

RED="\033[31m"
GREEN="\033[32m"
YELLOW="\033[33m"
NC="\033[0m"

echo -e "${GREEN}kep 一键安装脚本${NC}"


if [ "$(id -u)" != "0" ]; then
    echo -e "${RED}请使用 root 运行此脚本${NC}"
    exit 1
fi

ARCH=$(uname -m)
if [[ "$ARCH" != "x86_64" && "$ARCH" != "amd64" ]]; then
    echo -e "${RED}目前只支持 x86_64${NC}"
    exit 1
fi

echo "检测网络..."
if ! ping -c 2 1.1.1.1 >/dev/null 2>&1; then
    echo -e "${RED}没有网络连接${NC}"
    exit 1
fi


install_pkg () {

    if command -v apt >/dev/null 2>&1; then
        apt update
        apt install -y "$@"
    elif command -v dnf >/dev/null 2>&1; then
        dnf install -y "$@"
    elif command -v yum >/dev/null 2>&1; then
        yum install -y "$@"
    else
        echo -e "${RED}无法检测到包管理器${NC}"
        exit 1
    fi
}


check_cmd () {
    if ! command -v "$1" >/dev/null 2>&1; then
        echo -e "${YELLOW}$1 未安装，正在安装...${NC}"
        install_pkg "$1"
    else
        echo "$1 OK"
    fi
}

check_cmd wget
check_cmd unzip
check_cmd openssl
check_cmd tar


echo
read -p "安装目录 (默认 ~/kep): " Install_dir

if [ -z "$Install_dir" ]; then
    Install_dir="$HOME/kep"
fi

read -p "Web登录用户名: " WEB_USER
read -p "Web登录密码(至少8位): " WEB_PASS
echo
read -p "绑定域名: " DOMAIN

while [ ${#WEB_PASS} -lt 8 ]; do
    WEB_PASS="${WEB_PASS}0"
done

echo
read -p "HTTPS 监听端口 (默认443): " SSL_PORT
if [ -z "$SSL_PORT" ]; then
    SSL_PORT=443
fi

#echo
#echo "选择 HTTPS 证书模式"
#echo "1) Caddy 自动申请 Let's Encrypt (推荐)"
#echo "2) 自签名证书"

#read -p "请选择 [1-2] (默认1): " SSL_MODE

#if [ -z "$SSL_MODE" ]; then
#    SSL_MODE=1
#fi
SSL_MODE=2


API_TOKEN=$(openssl rand -hex 32)
LOCAL_TOKEN=$(openssl rand -hex 32)

echo "生成随机token..."


if [ -d "$Install_dir" ]; then
    echo -e "${YELLOW}目录已存在: $Install_dir${NC}"
else
    mkdir -p "$Install_dir"
fi

cd "$Install_dir"


echo "下载程序..."

wget https://github.com/stalltrix/kep-cli/releases/download/v0.1.9/kep-cli-linux-amd64.zip
wget https://github.com/stalltrix/kepweb/releases/download/v0.2.9/kepweb-linux-amd64.zip
wget https://github.com/stalltrix/kep-demo/releases/download/v0.3.1/kep-demo-linux-amd64.zip
wget https://github.com/stalltrix/kep-archive/releases/download/v20260329/kep-data.tar.gz
wget https://github.com/caddyserver/caddy/releases/download/v2.11.4/caddy_2.11.4_linux_amd64.tar.gz


tar -xzf kep-data.tar.gz
tar -xzf caddy_2.11.4_linux_amd64.tar.gz

unzip -o kep-cli-linux-amd64.zip
unzip -o kepweb-linux-amd64.zip
unzip -o kep-demo-linux-amd64.zip

chmod +x kep-cli-linux-amd64
chmod +x kepweb-linux-amd64
chmod +x kep-demo-linux-amd64
chmod +x caddy

if [ "$SSL_MODE" = "2" ]; then

openssl req -x509 -nodes \
-newkey rsa:2048 \
-days 3650 \
-keyout ${Install_dir}/ca.key \
-out ${Install_dir}/ca.crt \
-subj "/CN=localhost"

fi


./kep-cli-linux-amd64 -act=gen
./kep-cli-linux-amd64 -act=init


cat > core.json <<EOF
{
    "api_token": "$API_TOKEN",
    "listen": "127.0.0.1:13000",
    "ntp": "time.cloudflare.com",
    "local_token": "$LOCAL_TOKEN",
    "deny_file": "$Install_dir/deny.json",
    "token_file": "$Install_dir/token.json"
}
EOF

cat > web.json <<EOF
{
	"mainkey": "mainkey.pub",
	"pub_key": "pkey.pub",
	"priv_key": "pkey.priv",
	"sig_key": "pkey.sig",
	"domain": "$DOMAIN",
	"meta_on": true,
	"user": "$WEB_USER",
	"login_token": "$WEB_PASS",
	"api_token": "$API_TOKEN",
	"listen": "127.0.0.1:13001",
	"ntp": "time.cloudflare.com",
	"neighbors": [
		{
			"url": "http://127.0.0.1:13000",
			"token": "$LOCAL_TOKEN"
		}
	]
}
EOF

cat > token.json <<EOF
{}
EOF

if [ "$SSL_MODE" = "2" ]; then

cat > ${Install_dir}/caddy.json <<EOF
{
    "apps": {
        "http": {
            "servers": {
                "srv0": {
                    "listen": [
                        "0.0.0.0:${SSL_PORT}"
                    ],
                    "automatic_https": {
                        "disable": true
                    },
                    "routes": [
                        {
                            "match": [
                                {
                                    "path": [
                                        "/v1/*"
                                    ]
                                }
                            ],
                            "handle": [
                                {
                                    "handler": "reverse_proxy",
                                    "upstreams": [
                                        {
                                            "dial": "127.0.0.1:13000"
                                        }
                                    ]
                                }
                            ]
                        },
                        {
                            "handle": [
                                {
                                    "handler": "reverse_proxy",
                                    "upstreams": [
                                        {
                                            "dial": "127.0.0.1:13001"
                                        }
                                    ]
                                }
                            ]
                        }
                    ],
                    "tls_connection_policies": [
                        {
                            "certificate_selection": {
                                "any_tag": [
                                    "cert0"
                                ]
                            }
                        }
                    ]
                }
            }
        },
        "tls": {
            "certificates": {
                "load_files": [
                    {
                        "certificate": "${Install_dir}/ca.crt",
                        "key": "${Install_dir}/ca.key",
                        "tags": [
                            "cert0"
                        ]
                    }
                ]
            }
        }
    }
}
EOF

fi


cat > ${Install_dir}/run.sh <<EOF
#!/bin/bash
cd ${Install_dir}

setsid ${Install_dir}/kep-demo-linux-amd64 ${Install_dir}/core.json ${Install_dir}/core.log &
setsid ${Install_dir}/kepweb-linux-amd64 ${Install_dir}/web.json ${Install_dir}/web.log &

${Install_dir}/caddy run --config ${Install_dir}/caddy.json
EOF

chmod +x run.sh


cat > /etc/systemd/system/kep.service <<EOF
[Unit]
Description=Kep Service
After=network.target

[Service]
Type=simple
WorkingDirectory=$Install_dir
ExecStart=$Install_dir/run.sh
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
EOF

systemctl daemon-reload
systemctl enable kep
systemctl start kep


echo
echo "=============================="
echo -e "${GREEN}安装完成${NC}"
echo


echo "安装目录: $Install_dir"
echo "用户名: $WEB_USER"
echo "密码: $WEB_PASS"

echo
echo "API Token:"
echo "$API_TOKEN"

echo
echo "服务管理:"
echo "systemctl start kep"
echo "systemctl stop kep"
echo "systemctl status kep"
echo "=============================="
