#!/bin/bash

red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
plain='\033[0m'

cur_dir=$(pwd)

[[ $EUID -ne 0 ]] && echo -e "${red}Error:${plain} This script must be run as root user!\n" && exit 1

if [[ -f /etc/redhat-release ]]; then
    release="centos"
elif cat /etc/issue | grep -Eqi "debian"; then
    release="debian"
elif cat /etc/issue | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /etc/issue | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
elif cat /proc/version | grep -Eqi "debian"; then
    release="debian"
elif cat /proc/version | grep -Eqi "ubuntu"; then
    release="ubuntu"
elif cat /proc/version | grep -Eqi "centos|red hat|redhat|rocky|alma|oracle linux"; then
    release="centos"
else
    echo -e "${red}System version not detected, please contact the script author!${plain}\n" && exit 1
fi

arch=$(arch)

if [[ $arch == "x86_64" || $arch == "x64" || $arch == "amd64" ]]; then
    arch="64"
elif [[ $arch == "aarch64" || $arch == "arm64" ]]; then
    arch="arm64-v8a"
elif [[ $arch == "s390x" ]]; then
    arch="s390x"
else
    arch="64"
    echo -e "${red}Architecture detection failed, using default architecture: ${arch}${plain}"
fi

echo "Architecture: ${arch}"

if [ "$(getconf WORD_BIT)" != '32' ] && [ "$(getconf LONG_BIT)" != '64' ] ; then
    echo "This software is not supported on 32-bit systems (x86), please use 64-bit systems (x86_64). If there is an error in detection, please contact the author."
    exit 2
fi


# os version
if [[ -f /etc/os-release ]]; then
    os_version=$(awk -F'[= ."]' '/VERSION_ID/{print $3}' /etc/os-release)
fi
if [[ -z "$os_version" && -f /etc/lsb-release ]]; then
    os_version=$(awk -F'[= ."]+' '/DISTRIB_RELEASE/{print $2}' /etc/lsb-release)
fi

if [[ x"${release}" == x"centos" ]]; then
    if [[ ${os_version} -le 6 ]]; then
        echo -e "${red}Please use CentOS 7 or higher system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"ubuntu" ]]; then
    if [[ ${os_version} -lt 16 ]]; then
        echo -e "${red}Please use Ubuntu 16 or higher system!${plain}\n" && exit 1
    fi
elif [[ x"${release}" == x"debian" ]]; then
    if [[ ${os_version} -lt 8 ]]; then
        echo -e "${red}Please use Debian 8 or higher system!${plain}\n" && exit 1
    fi
fi

install_base() {
    if [[ x"${release}" == x"centos" ]]; then
        yum install epel-release -y
        yum install wget curl unzip tar crontabs socat -y
    else
        apt-get update -y
        apt install wget curl unzip tar cron socat -y
    fi
}

# 0: running, 1: not running, 2: not installed
check_status() {
    if [[ ! -f /etc/systemd/system/EzNode.service ]]; then
        return 2
    fi
    temp=$(systemctl status EzNode | grep Active | awk '{print $3}' | cut -d "(" -f2 | cut -d ")" -f1)
    if [[ x"${temp}" == x"running" ]]; then
        return 0
    else
        return 1
    fi
}

install_EzNode() {
    if [[ -e /usr/local/EzNode/ ]]; then
        rm -rf /usr/local/EzNode/
    fi

    mkdir /usr/local/EzNode/ -p
    cd /usr/local/EzNode/

    if  [ $# == 0 ] ;then
        last_version=$(curl -Ls "https://api.github.com/repos/overkillzero/EzNode/releases/latest" | grep '"tag_name":' | sed -E 's/.*"([^"]+)".*/\1/')
        if [[ ! -n "$last_version" ]]; then
            echo -e "${red}Failed to check EzNode version. It may be due to exceeding the Github API limit. Please try again later or manually specify the EzNode version for installation.${plain}"
            exit 1
        fi
        echo -e "Detected the latest version of EzNode: ${last_version}, starting installation"
        wget -q -N --no-check-certificate -O /usr/local/EzNode/EzNode-linux.zip https://github.com/overkillzero/EzNode/releases/download/${last_version}/EzNode-linux-${arch}.zip
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download EzNode. Please make sure your server can download files from Github.${plain}"
            exit 1
        fi
    else
        last_version=$1
        url="https://github.com/overkillzero/EzNode/releases/download/${last_version}/EzNode-linux-${arch}.zip"
        echo -e "Starting installation of EzNode v$1"
        wget -q -N --no-check-certificate -O /usr/local/EzNode/EzNode-linux.zip ${url}
        if [[ $? -ne 0 ]]; then
            echo -e "${red}Failed to download EzNode v$1. Please make sure the version exists.${plain}"
            exit 1
        fi
    fi

    unzip EzNode-linux.zip
    rm EzNode-linux.zip -f
    chmod +x EzNode
    mkdir /etc/EzNode/ -p
    rm /etc/systemd/system/EzNode.service -f
    file="https://github.com/overkillzero/EzNode/raw/master/EzNode.service"
    wget -q -N --no-check-certificate -O /etc/systemd/system/EzNode.service ${file}
    systemctl daemon-reload
    systemctl stop EzNode
    systemctl enable EzNode
    echo -e "${green}EzNode ${last_version}${plain} installation completed and set to start on boot"
    cp geoip.dat /etc/EzNode/
    cp geosite.dat /etc/EzNode/

    if [[ ! -f /etc/EzNode/config.yml ]]; then
        cp config.yml /etc/EzNode/
        echo -e ""
        echo -e "For a fresh installation, please refer to the tutorial: https://github.com/overkillzero/EzNode and configure the necessary content"
    else
        systemctl start EzNode
        sleep 2
        check_status
        echo -e ""
        if [[ $? == 0 ]]; then
            echo -e "${green}EzNode restarted successfully${plain}"
        else
            echo -e "${red}EzNode may have failed to start, please use EzNode log to view log information. If it cannot be started, it may have changed the configuration format, please go to the wiki for more information: https://github.com/EzNode-project/EzNode/wiki${plain}"
        fi
    fi

    if [[ ! -f /etc/EzNode/dns.json ]]; then
        cp dns.json /etc/EzNode/
    fi
    if [[ ! -f /etc/EzNode/route.json ]]; then
        cp route.json /etc/EzNode/
    fi
    if [[ ! -f /etc/EzNode/custom_outbound.json ]]; then
        cp custom_outbound.json /etc/EzNode/
    fi
    if [[ ! -f /etc/EzNode/custom_inbound.json ]]; then
        cp custom_inbound.json /etc/EzNode/
    fi
    if [[ ! -f /etc/EzNode/rulelist ]]; then
        cp rulelist /etc/EzNode/
    fi
    curl -o /usr/bin/EzNode -Ls https://raw.githubusercontent.com/overkillzero/EzNode/master/EzNode.sh
    chmod +x /usr/bin/EzNode
    ln -s /usr/bin/EzNode /usr/bin/eznode
    chmod +x /usr/bin/eznode
    cd $cur_dir
    rm -f install.sh
    echo -e ""
    echo "Usage of EzNode management script (compatible with EzNode execution, case-insensitive):"
    echo "------------------------------------------"
    echo "EzNode              - Show management menu (more functions)"
    echo "EzNode start        - Start EzNode"
    echo "EzNode stop         - Stop EzNode"
    echo "EzNode restart      - Restart EzNode"
    echo "EzNode status       - Check EzNode status"
    echo "EzNode enable       - Set EzNode to start on boot"
    echo "EzNode disable      - Disable EzNode to start on boot"
    echo "EzNode log          - Check EzNode logs"
    echo "EzNode generate     - Generate EzNode configuration file"
    echo "EzNode update       - Update EzNode"
    echo "EzNode update x.x.x - Update EzNode to specified version"
    echo "EzNode install      - Install EzNode"
    echo "EzNode uninstall    - Uninstall EzNode"
    echo "EzNode version      - Check EzNode version"
    echo "------------------------------------------"
}

echo -e "${green}Starting installation${plain}"
install_base
install_EzNode $1
