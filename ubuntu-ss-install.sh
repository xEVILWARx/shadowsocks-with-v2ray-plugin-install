#!/bin/sh

# Check system
if [ ! -f /etc/lsb-release ];then
    if ! grep -Eqi "ubuntu|debian" /etc/issue;then
        echo "\033[1;31mOnly Ubuntu or Debian can run this shell.\033[0m"
        exit 1
    fi
fi

# Make sure only root can run our script
[ `whoami` != "root" ] && echo "\033[1;31mThis script must be run as root.\033[0m" && exit 1

# Version
LIBSODIUM_VER=stable
MBEDTLS_VER=2.16.5
ss_file=0
v2_file=0
get_latest_ver(){
    ss_file=$(wget -qO- https://api.github.com/repos/shadowsocks/shadowsocks-libev/releases/latest | grep name | grep tar | cut -f4 -d\")
    v2_file=$(wget -qO- https://api.github.com/repos/shadowsocks/v2ray-plugin/releases/latest | grep linux-amd64 | grep name | cut -f4 -d\")
}

# Set shadowsocks-libev config password
set_password(){
    echo "\033[1;34mPlease enter password for shadowsocks-libev:\033[0m"
    read -p "(Default password: M3chD09):" shadowsockspwd
    [ -z "${shadowsockspwd}" ] && shadowsockspwd="M3chD09"
    echo "\033[1;35mpassword = ${shadowsockspwd}\033[0m"
}

# Set domain
set_domain(){
    echo "\033[1;34mPlease enter your domain:\033[0m"
    echo "If you don't have one, you can register one for free at:"
    echo "https://www.duckdns.org"
    read domain
    str=`echo $domain | grep '^\([a-zA-Z0-9_\-]\{1,\}\.\)\{1,\}[a-zA-Z]\{2,5\}'`
    while [ ! -n "${str}" ]
    do
        echo "\033[1;31mInvalid domain.\033[0m"
        echo "\033[1;31mPlease try again:\033[0m"
        read domain
        str=`echo $domain | grep '^\([a-zA-Z0-9_\-]\{1,\}\.\)\{1,\}[a-zA-Z]\{2,5\}'`
    done
    echo "\033[1;35mdomain = ${domain}\033[0m"
}



# Installation of shadowsocks-libev
install_ss(){
    if [ -f /usr/local/bin/ss-server ];then
        echo "\033[1;32mShadowsocks-libev already installed, skip.\033[0m"
    else
        apt install shadowsocks-libev -y
        systemctl stop shadowsocks-libev.service
        systemctl disable shadowsocks-libev.service
        if [ ! -f /usr/bin/ss-server ];then
            echo "\033[1;31mFailed to install shadowsocks-libev.\033[0m"
            exit 1
        fi
    fi
}


# Installation of v2ray-plugin
install_v2(){
    if [ -f /usr/local/bin/v2ray-plugin ];then
        echo "\033[1;32mv2ray-plugin already installed, skip.\033[0m"
    else
        if [ ! -f $v2_file ];then
            v2_url=$(wget -qO- https://api.github.com/repos/shadowsocks/v2ray-plugin/releases/latest | grep linux-amd64 | grep browser_download_url | cut -f4 -d\")
            wget $v2_url
        fi
        tar xf $v2_file
        chmod +x v2ray-plugin_linux_amd64
        mv v2ray-plugin_linux_amd64 /usr/local/bin/v2ray-plugin
        if [ ! -f /usr/local/bin/v2ray-plugin ];then
            echo "\033[1;31mFailed to install v2ray-plugin.\033[0m"
            exit 1
        fi
    fi
}

# Configure
ss_conf(){
    mkdir /etc/shadowsocks-libev
    cat >/etc/shadowsocks-libev/config.json << EOF
{
    "server":"0.0.0.0",
    "server_port":443,
    "password":"$shadowsockspwd",
    "timeout":300,
    "method":"chacha20-ietf-poly1305",
    "mode":"tcp_and_udp"
}
EOF
    cat >/etc/systemd/system/shadowv2.service << EOF
[Unit]
Description=Shadowsocks-libev Server Service
After=network.target
[Service]
ExecStart=ss-server -c /etc/shadowsocks-libev/config.json --plugin v2ray-plugin --plugin-opts "server;tls;host=$domain;cert=/etc/letsencrypt/live/$domain/fullchain.pem;key=/etc/letsencrypt/live/$domain/privkey.pem;loglevel=none"
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
[Install]
WantedBy=multi-user.target
EOF
}

get_cert(){
    if [ -f /etc/letsencrypt/live/$domain/fullchain.pem ];then
        echo "\033[1;32mcert already got, skip.\033[0m"
    else
        apt-get update
        if grep -Eqi "ubuntu" /etc/issue;then
            apt-get install -y certbot software-properties-common
        fi
        apt-get install -y certbot 
        certbot certonly --cert-name $domain -d $domain --standalone --agree-tos --register-unsafely-without-email
        systemctl enable certbot.timer
        systemctl start certbot.timer
        if [ ! -f /etc/letsencrypt/live/$domain/fullchain.pem ];then
            echo "\033[1;31mFailed to get cert.\033[0m"
            exit 1
        fi
    fi
}

start_ss(){
    chmod 644 /etc/systemd/system/shadowv2.service
    systemctl daemon-reload
    systemctl status shadowv2.service > /dev/null 2>&1
    if [ $? -eq 0 ]; then
        systemctl stop shadowv2.service
    fi
    systemctl enable shadowv2.service
    systemctl start shadowv2.service
}


print_ss_info(){
    clear
    echo "\033[1;32mCongratulations, Shadowsocks-libev server install completed\033[0m"
    echo "Your Server IP        :  ${domain} "
    echo "Your Server Port      :  443 "
    echo "Your Password         :  ${shadowsockspwd} "
    echo "Your Encryption Method:  chacha20-ietf-poly1305 "
    echo "Your Plugin           :  v2ray-plugin"
    echo "Your Plugin options   :  tls;host=${domain};loglevel=none"
    echo "Enjoy it!"
}

install_all(){
    set_password
    set_domain
    get_latest_ver
    install_ss
    install_v2
    ss_conf
    get_cert
    start_ss
    remove_files
    print_ss_info
}

remove_all(){
    systemctl disable shadowv2.service
    systemctl stop shadowv2.service
    rm -fr /etc/shadowsocks-libev
    rm -f /usr/local/bin/ss-local
    rm -f /usr/local/bin/ss-tunnel
    rm -f /usr/local/bin/ss-server
    rm -f /usr/local/bin/ss-manager
    rm -f /usr/local/bin/ss-redir
    rm -f /usr/local/bin/ss-nat
    rm -f /usr/local/bin/v2ray-plugin
    rm -f /usr/local/lib/libshadowsocks-libev.a
    rm -f /usr/local/lib/libshadowsocks-libev.la
    rm -f /usr/local/include/shadowsocks.h
    rm -f /usr/local/lib/pkgconfig/shadowsocks-libev.pc
    rm -f /usr/local/share/man/man1/ss-local.1
    rm -f /usr/local/share/man/man1/ss-tunnel.1
    rm -f /usr/local/share/man/man1/ss-server.1
    rm -f /usr/local/share/man/man1/ss-manager.1
    rm -f /usr/local/share/man/man1/ss-redir.1
    rm -f /usr/local/share/man/man1/ss-nat.1
    rm -f /usr/local/share/man/man8/shadowsocks-libev.8
    rm -fr /usr/local/share/doc/shadowsocks-libev
    rm -f /usr/lib/systemd/system/shadowsocks.service
    echo "\033[1;32mRemove success!\033[0m"
}

clear
echo "What do you want to do?"
echo "[1] Install"
echo "[2] Remove"
read -p "(Default option: Install):" option
option=${option:-1}
if [ $option -eq 2 ];then
    remove_all
else
    install_all
fi
