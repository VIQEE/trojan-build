#!/bin/bash
sys=$(cat /etc/issue)
un="Ubuntu"
de="Debian"

if [[ "$(echo "$sys" | grep "$de")" == "" ]] && [[ "$(echo "$sys" | grep "$un")" == "" ]];then
	echo -e "\033[31m 该脚本不支持此系统！\033[0m"
fi
ver='v1.1'
function blue(){
    echo -e "\033[34m\033[01m $1 \033[0m"
}
function green(){
    echo -e "\033[32m\033[01m $1 \033[0m"
}
function red(){
    echo -e "\033[31m\033[01m $1 \033[0m"
}
function grey(){
    echo -e "\033[36m\033[01m $1 \033[0m"
}
netstat >> /dev/null 2>&1
if [[ $(echo $?) != 0 ]];then
    apt install -y net-tools
fi

check_status(){
    check_trojan_status(){
        netstat -ntlp | grep trojan >> /dev/null 2>&1
        if [[ $(echo $?) != 0 ]];then
            red "未运行"
        else
            green "已运行"
        fi 
    }
    if [[ ! -e '/usr/local/bin/trojan' ]] || [[ ! -f '/usr/local/etc/trojan/config.json' ]];then
    	echo -n "当前状态: trojan"
        echo -en "\033[31m\033[01m 未安装\033[0m"
        check_trojan_status
    else
	echo -n "当前状态: trojan"
        echo -en "\033[32m\033[01m 已安装\033[0m"
        check_trojan_status
    fi
}

install_nginx(){
    apt update && apt upgrade -y && apt install sudo
    sudo apt install -y curl gnupg2 ca-certificates lsb-release
    apt -y --purge remove nginx*
    apt -y autoremove
    echo "deb http://nginx.org/packages/mainline/debian `lsb_release -cs` nginx" \
| sudo tee /etc/apt/sources.list.d/nginx.list
    curl -fsSL https://nginx.org/keys/nginx_signing.key | sudo apt-key add -
    sudo apt update
    sudo apt install nginx
}

config_cert(){
    sudo apt install -y socat cron curl
    sudo systemctl start cron
    sudo systemctl enable cron 
    sudo mkdir /usr/local/etc/certfiles
    curl  https://get.acme.sh | sh
    blue "========================="
    read -p "输入你的APIkey：" APIkey
    blue "========================="
    read -p "输入你的APISecret：" APISecret
    blue "========================="
    read -p "输入已解析到服务器的域名：" domain
    blue "========================="
    export Ali_Key="$APIkey"
    export Ali_Secret="$APISecret"
    .acme.sh/acme.sh --issue -d ${domain} -d www.${domain} --dns dns_ali
    .acme.sh/acme.sh --install-cert -d ${domain} -d www.${domain} --key-file /usr/local/etc/certfiles/private.key --fullchain-file /usr/local/etc/certfiles/certificate.crt
    .acme.sh/acme.sh  --upgrade  --auto-upgrade
}

install_trojan(){
    sudo apt install -y libcap2-bin xz-utils
    sudo bash -c "$(curl -fsSL https://raw.githubusercontent.com/trojan-gfw/trojan-quickstart/master/trojan-quickstart.sh)"
    sudo cp /usr/local/etc/trojan/config.json /usr/local/etc/trojan/config.json.bak
cat > /usr/local/etc/trojan/config.json << "EOF"
{
  "run_type": "server",
  "local_addr": "0.0.0.0",
  "local_port": 443,
  "remote_addr": "127.0.0.1",
  "remote_port": 80,
  "password": [
  	"password1"
  ],
  "log_level": 1,
  "ssl": {
    "cert": "/usr/local/etc/certfiles/certificate.crt",
    "key": "/usr/local/etc/certfiles/private.key",
    "key_password": "",
    "cipher": "ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-SHA384:ECDHE-RSA-AES256-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256",
    "prefer_server_cipher": true,
    "alpn": [
      "http/1.1"
    ],
    "reuse_session": true,
    "session_ticket": false,
    "session_timeout": 600,
    "plain_http_response":  "",
    "curves": "",
    "dhparam": ""
  },
  "tcp": {
    "prefer_ipv4": false,
    "no_delay": true,
    "keep_alive": true,
    "fast_open": false,
    "fast_open_qlen": 20
  },
  "mysql": {
    "enabled": false,
    "server_addr": "127.0.0.1",
    "server_port": 3306,
    "database": "trojan",
    "username": "trojan",
    "password": ""
  }
}
EOF
    set_passwd(){
        blue "++++++++++++++++++++++++"
    	read -p "请输入为trojan设置的密码：" passwd
        blue "++++++++++++++++++++++++"
	read -p "请再次输入密码：" passwd1
        blue "++++++++++++++++++++++++"
    }
    for i in $(seq 1 10)
    do
      set_passwd
      if [ "$passwd" == "$passwd1" ];then
	  break
      else
          red "两次输入不一致，请重新输入！"
      fi
    done
    sed -i "s/password1/$passwd/" /usr/local/etc/trojan/config.json
    sudo systemctl daemon-reload
    echo "0 0 1 * * killall -s SIGUSR1 trojan" >> /var/spool/cron/crontabs/$(whoami)
}  

config_nginx(){
    rm -rf /etc/nginx/conf.d/default.conf
    touch /etc/nginx/conf.d/0.trojan.conf
    ip_name=$(curl ifconfig.me)
    cat > /etc/nginx/conf.d/0.trojan.conf << "EOF"
server {
    listen 127.0.0.1:80 default_server;

    server_name <tdom.ml>;

    location / {
        proxy_pass https://github.com/voiin;
        proxy_set_header Host $proxy_host;
        proxy_set_header X-Real-IP $remote_addr;
        proxy_set_header X-Remote-Port $proxy_add_x_forwarded_for;
        proxy_set_header X-Remote-Port $remote_port;
        proxy_set_header X-Forwarded-Proto $scheme;
        proxy_redirect off;
    }
}

server {
    listen 127.0.0.1:80;

    server_name <10.10.10.10>;

    return 301 https://<tdom.ml>$request_uri;
}

server {
    listen 0.0.0.0:80;
    listen [::]:80;

    server_name _;

    return 301 https://<tdom.ml>$request_uri;
}
EOF
    sed -i "s/<tdom.ml>/$domain/" /etc/nginx/conf.d/0.trojan.conf
    sed -i "s/<10.10.10.10>/${ip_name}/" /etc/nginx/conf.d/0.trojan.conf
}

start_trojan(){
    nginx -t
    nginx -c /etc/nginx/nginx.conf
    nginx -s reload
    sudo systemctl restart trojan
    sudo systemctl enable trojan
    sudo systemctl enable nginx
    green "--------------------"
    green "--------------------"
    green "###trojan启动完成###"
    green "--------------------"
    green "--------------------"
}

remove_trojan(){
    systemctl stop trojan
    rm -rf .acme.sh
    rm -rf /var/spool/cron/crontabs/$(whoami)
    rm -rf /etc/systemd/system/trojan.service
    rm -rf /etc/nginx/conf.d/0.trojan.conf
    rm -rf /usr/local/etc/certfiles
    rm -rf /usr/local/bin/trojan 
    rm -f /usr/local/etc/trojan/config.json
    green "###trojan卸载完成###"
}

start_menu(){
    clear 
    echo -n "trojan一键安装管理脚本" 
    red "[${ver}]"
grey "===================================
#  System Required: CentOS 7+,Debian 9+,Ubuntu 16+
#  Version: 1.1
#  Author: 韦岐
#  Blogs: https://voiin.com/ && https://www.axrni.cn
==================================="
echo -e "\033[32m 1.\033[0m 安装trojan"
echo -e "\033[32m 2.\033[0m 卸载trojan"
echo -e "\033[32m 3.\033[0m 退出脚本"
grey "==================================="
    check_status
    read -p "请输入数字[1-3]:" num
    case "$num" in
        1)
	install_nginx
	config_cert
	install_trojan
	config_nginx
	start_trojan
	;;
        2)
	remove_trojan
	;;
        3)
	exit 1
	;;
        *)
	clear
	red "请输入正确数字"
	sleep 5s
	start_menu
	;;
    esac
}
start_menu
