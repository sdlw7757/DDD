#!/bin/bash
# ============================================================
# 增强版全能网络安装脚本
# 特性：Ubuntu/Debian/CentOS 网络自动安装（不依赖RAW镜像）
#       支持 Ubuntu 20.04/22.04/24.04/26.04
#       支持 Debian 10/11/12/13
#       支持 CentOS 7/8/9-stream
# 快捷唤起：输入 y/Y 直接调用 | 默认密码123456（可自定义）
# ============================================================

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[34m"
Plain="\033[0m"

SCRIPT_PATH="/usr/local/bin/ddtool.sh"
LOG_FILE="/var/log/dd_tool.log"
DEFAULT_PASS="123456"
RETRY_TIMES=3

log() {
    local LEVEL=$1
    local MSG=$2
    echo -e "[$(date +%Y-%m-%d\ %H:%M:%S)] [$LEVEL] $MSG" >> "$LOG_FILE"
    case $LEVEL in
        INFO)  echo -e "${Green}[INFO] $MSG${Plain}" ;;
        WARN)  echo -e "${Yellow}[WARN] $MSG${Plain}" ;;
        ERROR) echo -e "${Red}[ERROR] $MSG${Plain}" ;;
        DEBUG) echo -e "${Blue}[DEBUG] $MSG${Plain}" ;;
    esac
}

err_exit() {
    log "ERROR" "$1"
    exit 1
}

smart_install() {
    local pkg="$1"
    if command -v yum &>/dev/null; then
        yum install -y "$pkg" || { log "WARN" "$pkg 安装失败"; return 1; }
    elif command -v apt &>/dev/null; then
        apt update -y && apt install -y "$pkg" || { log "WARN" "$pkg 安装失败"; return 1; }
    else
        log "ERROR" "不支持的包管理器"
        return 1
    fi
    return 0
}

make_short_url() {
    clear
    log "INFO" "========== 一键生成永久短链接 =========="
    read -p "请输入需要缩短的长链接：" long_url
    [ -z "$long_url" ] && err_exit "链接不能为空！"
    short_url=$(curl -sF "shorten=$long_url" http://ttm.sh)
    if [[ "$short_url" == http* ]]; then
        log "INFO" "✅ 永久短链接生成成功！"
        echo -e "${Green}原始链接：${Plain} $long_url"
        echo -e "${Green}永久短链：${Plain} $short_url"
        echo -e "${Green}一键命令：${Plain} bash <(curl -sSL $short_url)"
    else
        err_exit "生成失败，请检查链接是否有效"
    fi
}

# ===================== 网络安装核心函数 =====================
get_interface() {
    local iface=""
    local Interfaces=$(cat /proc/net/dev | grep ':' | cut -d':' -f1 | sed 's/\s//g' | grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap\|^ip6gre\|^ip6tnl\|^teql\|^ocserv\|^vpn')
    local defaultRoute=$(ip route show default | grep "^default")
    for item in $Interfaces; do
        [ -n "$item" ] || continue
        echo "$defaultRoute" | grep -q "$item"
        [ $? -eq 0 ] && iface="$item" && break
    done
    echo "$iface"
}

netmask() {
    n="${1:-32}"
    b=""
    m=""
    for((i=0;i<32;i++)); do
        [ $i -lt $n ] && b="${b}1" || b="${b}0"
    done
    for((i=0;i<4;i++)); do
        s=$(echo "$b"|cut -c$[$[$i*8]+1]-$[$[$i+1]*8])
        [ "$m" == "" ] && m="$((2#${s}))" || m="${m}.$((2#${s}))"
    done
    echo "$m"
}

get_ip_static() {
    local iface=$(get_interface)
    [ -z "$iface" ] && iface="eth0"
    local iAddr=$(ip addr show dev "$iface" | grep "inet.*" | head -n1 | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\/[0-9]\{1,2\}')
    echo "$iAddr" | grep '^10\.' | grep '/32$' >/dev/null && iAddr=$(echo "$iAddr" | sed 's/\/32/\/24/')
    local ipAddr=$(echo ${iAddr} | cut -d'/' -f1)
    local ipMask=$(netmask $(echo ${iAddr} | cut -d'/' -f2))
    local ipGate=$(ip route show default | grep "^default" | grep -o '[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}\.[0-9]\{1,3\}' | head -n1)
    echo "$ipAddr $ipMask $ipGate"
}

select_mirror() {
    local distro="$1"
    local distname="$2"
    local arch="$3"
    declare -A mirrors
    case "$distro" in
        debian)
            mirrors=(["tuna"]="https://mirrors.tuna.tsinghua.edu.cn/debian" ["ustc"]="https://mirrors.ustc.edu.cn/debian" ["163"]="http://mirrors.163.com/debian")
            path="dists/${distname}/main/installer-${arch}/current/images/netboot/debian-installer/${arch}/initrd.gz"
            ;;
        ubuntu)
            mirrors=(["tuna"]="https://mirrors.tuna.tsinghua.edu.cn/ubuntu" ["ustc"]="https://mirrors.ustc.edu.cn/ubuntu" ["aliyun"]="http://mirrors.aliyun.com/ubuntu")
            legacy=""; [ "$distname" = "focal" ] && legacy="legacy-"
            path="dists/${distname}/main/installer-${arch}/current/${legacy}images/netboot/ubuntu-installer/${arch}/initrd.gz"
            ;;
        centos)
            mirrors=(["tuna"]="https://mirrors.tuna.tsinghua.edu.cn/centos" ["ustc"]="https://mirrors.ustc.edu.cn/centos" ["aliyun"]="http://mirrors.aliyun.com/centos")
            path="${distname}/os/${arch}/isolinux/initrd.img"
            ;;
        *) return 1 ;;
    esac
    for name in "${!mirrors[@]}"; do
        base="${mirrors[$name]}"
        url="$base/$path"
        wget --no-check-certificate --spider --timeout=3 -q "$url" && echo "$base" && return 0
    done
    return 1
}

netinstall_linux() {
    local os_type="$1"
    local version_codename="$2"
    local version_display="$3"
    local root_pass="$4"
    local ssh_port="$5"
    local use_dhcp="$6"
    local static_ip_info="$7"
    local dns="$8"

    local arch=$(uname -m)
    case "$arch" in
        x86_64|amd64) arch="amd64" ;;
        i386|i686) arch="i386" ;;
        aarch64|arm64) arch="arm64" ;;
        *) err_exit "不支持的架构: $arch" ;;
    esac

    local ip_addr="" ip_mask="" ip_gate=""
    if [ "$use_dhcp" = "y" ]; then
        read ip_addr ip_mask ip_gate <<< $(get_ip_static)
        [ -z "$ip_addr" ] && err_exit "无法获取当前IP，请手动指定静态IP"
        log "INFO" "检测到当前IP: $ip_addr, 掩码: $ip_mask, 网关: $ip_gate，将使用DHCP模式"
    else
        read ip_addr ip_mask ip_gate <<< "$static_ip_info"
        [ -z "$ip_addr" ] && err_exit "静态IP信息不全"
    fi

    log "INFO" "正在测试可用镜像源（$os_type $version_display）..."
    local mirror=$(select_mirror "${os_type,,}" "$version_codename" "$arch")
    if [ -z "$mirror" ]; then
        err_exit "无法找到可用的镜像源，请检查网络或稍后重试"
    fi
    log "INFO" "使用镜像源: $mirror"

    mkdir -p /tmp/netinstall
    cd /tmp/netinstall || err_exit "无法进入临时目录"
    log "INFO" "下载内核和初始化映像..."
    if [ "$os_type" = "CentOS" ]; then
        wget --no-check-certificate -q "$mirror/$version_codename/os/$arch/isolinux/vmlinuz" -O vmlinuz || err_exit "下载 vmlinuz 失败"
        wget --no-check-certificate -q "$mirror/$version_codename/os/$arch/isolinux/initrd.img" -O initrd.img || err_exit "下载 initrd.img 失败"
    else
        local legacy=""; [ "$version_codename" = "focal" ] && legacy="legacy-"
        if [ "$os_type" = "Ubuntu" ]; then
            wget --no-check-certificate -q "$mirror/dists/$version_codename/main/installer-$arch/current/${legacy}images/netboot/ubuntu-installer/$arch/linux" -O vmlinuz || err_exit "下载 vmlinuz 失败"
            wget --no-check-certificate -q "$mirror/dists/$version_codename/main/installer-$arch/current/${legacy}images/netboot/ubuntu-installer/$arch/initrd.gz" -O initrd.img || err_exit "下载 initrd.img 失败"
        else
            wget --no-check-certificate -q "$mirror/dists/$version_codename/main/installer-$arch/current/images/netboot/debian-installer/$arch/linux" -O vmlinuz || err_exit "下载 vmlinuz 失败"
            wget --no-check-certificate -q "$mirror/dists/$version_codename/main/installer-$arch/current/images/netboot/debian-installer/$arch/initrd.gz" -O initrd.img || err_exit "下载 initrd.img 失败"
        fi
    fi

    local crypt_pass=$(openssl passwd -1 "$root_pass")
    local interface=$(get_interface)
    [ -z "$interface" ] && interface="eth0"
    local mirror_host=$(echo "$mirror" | awk -F'://' '{print $2}' | cut -d'/' -f1)
    local mirror_path=$(echo "$mirror" | awk -F'://' '{print $2}' | cut -d'/' -f2-)
    [ -z "$mirror_path" ] && mirror_path="/"

    if [ "$os_type" = "CentOS" ]; then
        cat > ks.cfg <<EOF
install
url --url="$mirror/$version_codename/os/$arch/"
rootpw --iscrypted $crypt_pass
text
reboot
lang en_US
keyboard us
timezone Asia/Shanghai
network --bootproto=static --ip=$ip_addr --netmask=$ip_mask --gateway=$ip_gate --nameserver=$dns --device=$interface --onboot=on
bootloader --location=mbr --driveorder=sda
zerombr
clearpart --all --initlabel
autopart
%packages
@base
%end
EOF
        gzip -d initrd.img
        echo ks.cfg | cpio -o -H newc -A -F initrd.img 2>/dev/null
        gzip initrd.img
        boot_options="ks=file://ks.cfg"
    else
        cat > preseed.cfg <<EOF
d-i debian-installer/locale string en_US.UTF-8
d-i keyboard-configuration/xkb-keymap select us
d-i netcfg/choose_interface select $interface
d-i netcfg/disable_autoconfig boolean true
d-i netcfg/dhcp_failed note
d-i netcfg/dhcp_options select Configure network manually
d-i netcfg/get_ipaddress string $ip_addr
d-i netcfg/get_netmask string $ip_mask
d-i netcfg/get_gateway string $ip_gate
d-i netcfg/get_nameservers string $dns
d-i netcfg/confirm_static boolean true
d-i mirror/country string manual
d-i mirror/http/hostname string $mirror_host
d-i mirror/http/directory string $mirror_path
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password $crypt_pass
d-i clock-setup/utc boolean true
d-i time/zone string Asia/Shanghai
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select atomic
d-i partman-partitioning/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string /dev/sda
d-i finish-install/reboot_in_progress note
d-i preseed/late_command string \
    in-target sed -ri 's/^#?Port.*/Port ${ssh_port}/g' /etc/ssh/sshd_config; \
    in-target sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/g' /etc/ssh/sshd_config; \
    in-target sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/g' /etc/ssh/sshd_config;
EOF
        gzip -d initrd.img
        echo preseed.cfg | cpio -o -H newc -A -F initrd.img 2>/dev/null
        gzip initrd.img
        boot_options="auto=true priority=critical preseed/file=/preseed.cfg"
    fi

    cp vmlinuz /boot/vmlinuz.netinstall
    cp initrd.img /boot/initrd.img.netinstall
    chmod 644 /boot/vmlinuz.netinstall /boot/initrd.img.netinstall

    local grub_cfg=""
    if [ -f /boot/grub/grub.cfg ]; then
        grub_cfg="/boot/grub/grub.cfg"
    elif [ -f /boot/grub2/grub.cfg ]; then
        grub_cfg="/boot/grub2/grub.cfg"
    else
        err_exit "未找到 GRUB 配置文件"
    fi

    cat > /tmp/grub.new <<EOF
menuentry "Network Install $os_type $version_display" {
    linux /boot/vmlinuz.netinstall $boot_options
    initrd /boot/initrd.img.netinstall
}
EOF
    sed -i "/^menuentry /i $(cat /tmp/grub.new | sed 's/\//\\\//g')" "$grub_cfg"
    log "INFO" "GRUB 启动项添加成功，系统将在重启后自动进入网络安装"
    read -p "按回车键立即重启..."
    reboot
}

# ---------------------- 初始化脚本自身 ----------------------
if [ ! -f "$SCRIPT_PATH" ]; then
    cp "$0" "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH" || err_exit "无法写入全局脚本"
    grep -q "alias y='$SCRIPT_PATH'" /etc/profile || echo "alias y='$SCRIPT_PATH'" >> /etc/profile
    grep -q "alias Y='$SCRIPT_PATH'" /etc/profile || echo "alias Y='$SCRIPT_PATH'" >> /etc/profile
    source /etc/profile >/dev/null 2>&1
    log "INFO" "全局别名配置完成！输入 y/Y 即可调用本脚本"
    sleep 1
fi

[ $EUID -ne 0 ] && err_exit "必须使用root用户执行！"
mkdir -p "$(dirname "$LOG_FILE")"

# ===================== 主菜单 =====================
while true; do
    clear
    log "INFO" "==================== 全能网络安装脚本 ===================="
    log "INFO" "功能：网络安装 | 面板 | 优化 | 测速 | 硬件 | 路由 | 系统管理 | Docker | 短链接"
    log "WARN" "⚠️ 1-3选项为网络自动安装（会清空磁盘），请谨慎操作！"
    echo ""
    echo "==================== 主菜单 ===================="
    echo "【1】Ubuntu 网络自动安装"
    echo "【2】Debian 网络自动安装"
    echo "【3】CentOS 网络自动安装"
    echo ""
    echo "【4】一键安装/修复/清理 宝塔面板"
    echo "【5】一键安装/修复/清理 1Panel面板"
    echo "【6】服务器一键性能网络安全优化"
    echo "【7】一键全网测速脚本（稳定版，结果导出）"
    echo "【8】一键查看服务器硬件完整配置（导出报告）"
    echo "【9】一键三网回程路由追踪测试（可视化）"
    echo ""
    echo "【10】查看操作日志"
    echo "【11】系统信息查询（完整硬件检测）"
    echo "【12】系统一键更新（内核+软件包）"
    echo "【13】系统安全清理（释放空间）"
    echo "【14】安装基础必备工具"
    echo "【15】Docker 一站式管理（安装/卸载/更新/容器）"
    echo "【16】一键生成永久短链接（永不过期）"
    echo "【17】退出脚本"
    read -p "请输入功能序号（1-17）：" main_opt

    case $main_opt in
        16)
            make_short_url
            read -p "按回车键返回主菜单..."
            continue
            ;;
        4)
            clear
            log "INFO" "==================== 宝塔面板管理 ===================="
            echo "【1】安装 / 修复 宝塔面板"
            echo "【2】彻底清理 / 卸载 宝塔面板（危险）"
            read -p "请选择操作：" bt_opt
            case $bt_opt in
                1)
                    log "INFO" "开始安装/修复宝塔面板..."
                    smart_install wget curl
                    wget -O install.sh https://download.bt.cn/install/install_lts.sh
                    chmod +x install.sh
                    bash install.sh --repair
                    log "INFO" "宝塔面板安装/修复完成！"
                    ;;
                2)
                    log "WARN" "⚠️ 即将彻底卸载宝塔面板，所有数据将被删除！"
                    read -p "确定继续？(y/n)：" bt_confirm
                    if [ "$bt_confirm" = "y" ]; then
                        wget -O uninstall.sh https://download.bt.cn/install/uninstall.sh
                        chmod +x uninstall.sh
                        bash uninstall.sh
                        rm -rf /www /bt /server /panels
                        log "INFO" "✅ 宝塔已彻底清理完成！"
                    else
                        log "INFO" "已取消"
                    fi
                    ;;
                *) log "ERROR" "无效选项" ;;
            esac
            read -p "按回车键返回主菜单..."
            continue
            ;;
        5)
            clear
            log "INFO" "==================== 1Panel 面板管理 ===================="
            echo "【1】安装 / 升级 1Panel 面板"
            echo "【2】彻底清理 / 卸载 1Panel 面板（危险）"
            read -p "请选择操作：" op_opt
            case $op_opt in
                1)
                    log "INFO" "开始安装/升级1Panel..."
                    smart_install wget curl
                    if [ -f "/usr/local/1panel/1panel" ]; then
                        curl -sSL https://resource.1panel.hk/update.sh | bash
                    else
                        curl -sSL https://resource.1panel.hk/quick_install.sh | bash
                    fi
                    log "INFO" "1Panel 操作完成！"
                    ;;
                2)
                    log "WARN" "⚠️ 即将彻底卸载1Panel，所有数据将被删除！"
                    read -p "确定继续？(y/n)：" op_confirm
                    if [ "$op_confirm" = "y" ]; then
                        systemctl stop 1panel
                        systemctl disable 1panel
                        rm -rf /usr/local/1panel /var/lib/1panel /etc/1panel /var/log/1panel /usr/bin/1panel
                        log "INFO" "✅ 1Panel 已彻底清理完成！"
                    else
                        log "INFO" "已取消"
                    fi
                    ;;
                *) log "ERROR" "无效选项" ;;
            esac
            read -p "按回车键返回主菜单..."
            continue
            ;;
        6)
            log "INFO" "执行增强版服务器优化..."
            timedatectl set-timezone Asia/Shanghai && log "INFO" "时区已同步为上海"
            cat > /etc/security/limits.d/99-custom.conf << EOF
* soft nofile 65535
* hard nofile 65535
root soft nofile 65535
root hard nofile 65535
* soft nproc 65535
* hard nproc 65535
EOF
            log "INFO" "文件描述符限制已优化"
            cat > /etc/sysctl.d/99-custom.conf << EOF
net.ipv4.tcp_syncookies = 1
net.ipv4.tcp_tw_reuse = 1
net.ipv4.tcp_fin_timeout = 30
net.ipv4.tcp_keepalive_time = 600
net.ipv4.tcp_max_syn_backlog = 8192
net.core.somaxconn = 65535
net.core.rmem_max = 67108864
net.core.wmem_max = 67108864
net.ipv4.tcp_rmem = 4096 87380 67108864
net.ipv4.tcp_wmem = 4096 65536 67108864
net.ipv6.conf.all.disable_ipv6 = 1
net.ipv4.tcp_max_tw_buckets = 5000
net.ipv4.ip_local_port_range = 1024 65535
vm.swappiness = 10
vm.dirty_ratio = 10
vm.dirty_background_ratio = 5
EOF
            sysctl --system >/dev/null 2>&1 && log "INFO" "内核参数已优化"
            sed -i 's/^#PermitRootLogin.*/PermitRootLogin prohibit-password/g' /etc/ssh/sshd_config
            sed -i 's/^#PasswordAuthentication.*/PasswordAuthentication no/g' /etc/ssh/sshd_config
            systemctl restart sshd 2>/dev/null || service ssh restart && log "INFO" "SSH安全配置已更新"
            setenforce 0 >/dev/null 2>&1 || true
            sed -i 's/^SELINUX=.*/SELINUX=disabled/g' /etc/selinux/config 2>/dev/null || true
            systemctl disable firewalld >/dev/null 2>&1 || ufw disable >/dev/null 2>&1 || true
            log "INFO" "安全策略已优化"
            echo "net.core.default_qdisc=fq" >> /etc/sysctl.conf
            echo "net.ipv4.tcp_congestion_control=bbr" >> /etc/sysctl.conf
            sysctl -p >/dev/null 2>&1
            log "INFO" "BBR网络加速已开启"
            log "INFO" "✅ 服务器优化完成！建议重启生效"
            read -p "是否立即重启？(y/n):" rboot
            [ "$rboot" = "y" ] && reboot
            read -p "按回车键返回主菜单..."
            continue
            ;;
        7)
            log "INFO" "运行稳定版全网测速脚本..."
            smart_install wget curl bc
            curl -sL yabs.sh | bash -s -- -5 -9 | tee /root/speedtest_result.txt
            log "INFO" "测速完成！结果已导出至 /root/speedtest_result.txt"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        8)
            log "INFO" "生成服务器硬件配置报告..."
            REPORT_FILE="/root/server_hardware_$(date +%Y%m%d).txt"
            echo "========== 服务器硬件配置报告 $(date) ==========" > "$REPORT_FILE"
            echo -e "\n【CPU信息】" >> "$REPORT_FILE"; lscpu >> "$REPORT_FILE" 2>/dev/null
            echo -e "\n【内存信息】" >> "$REPORT_FILE"; free -h >> "$REPORT_FILE"
            echo -e "\n【磁盘信息】" >> "$REPORT_FILE"; lsblk >> "$REPORT_FILE" 2>/dev/null; df -h >> "$REPORT_FILE"
            echo -e "\n【网卡&IP信息】" >> "$REPORT_FILE"; ip addr >> "$REPORT_FILE" 2>/dev/null
            echo -e "\n【系统版本】" >> "$REPORT_FILE"; cat /etc/os-release >> "$REPORT_FILE"
            log "INFO" "✅ 硬件配置报告已生成：$REPORT_FILE"
            cat "$REPORT_FILE"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        9)
            log "INFO" "运行三网回程路由测试..."
            smart_install wget curl mtr traceroute
            bash <(curl -sSL https://raw.githubusercontent.com/lidabruce/backhaul/master/backhaul.sh) -v
            log "INFO" "三网回程测试完成！"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        10)
            log "INFO" "查看操作日志（最后100行）"
            tail -n 100 "$LOG_FILE"
            read -p "是否查看完整日志？(y/n)：" view_all
            [ "$view_all" = "y" ] && less "$LOG_FILE"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        11)
            clear
            log "INFO" "========== 系统完整信息查询 =========="
            echo "【1】系统基础信息 【2】CPU信息 【3】内存信息"
            echo "【4】磁盘信息   【5】网络信息 【6】虚拟化信息 【7】导出完整报告"
            read -p "请选择：" sysinfo_opt
            case $sysinfo_opt in
                1) hostnamectl; cat /etc/os-release | grep -E "NAME|VERSION"; uname -r; uptime -p ;;
                2) lscpu | grep -E "Model name|CPU MHz|CPU|Core" ;;
                3) free -h; swapon --show ;;
                4) lsblk; df -h --total ;;
                5) ip -br addr; echo -n "公网IPv4："; curl -s 4.ipw.cn; echo ;;
                6) virt-what 2>/dev/null; dmidecode -s system-manufacturer 2>/dev/null ;;
                7) REPORT="/root/sysinfo_$(date +%Y%m%d).log"; echo "===== 系统完整报告 =====" > "$REPORT"; cat /etc/os-release >> "$REPORT"; lscpu >> "$REPORT"; free -h >> "$REPORT"; lsblk >> "$REPORT"; ip addr >> "$REPORT"; log "INFO" "报告已生成：$REPORT" ;;
                *) log "ERROR" "无效选项" ;;
            esac
            read -p "按回车键返回主菜单..."
            continue
            ;;
        12)
            log "INFO" "开始系统一键更新..."
            if command -v apt &>/dev/null; then
                apt update -y && apt upgrade -y && apt dist-upgrade -y && apt autoremove -y --purge
            elif command -v yum &>/dev/null; then
                yum update -y && dnf update -y 2>/dev/null
            fi
            log "INFO" "✅ 系统更新完成！"
            read -p "是否立即重启？(y/n)：" reboot_now
            [ "$reboot_now" = "y" ] && reboot
            read -p "按回车键返回主菜单..."
            continue
            ;;
        13)
            log "INFO" "开始系统安全清理..."
            if command -v apt &>/dev/null; then
                apt clean all && apt autoremove -y --purge
                rm -rf /var/log/*.gz /var/log/*.[0-9] /var/cache/apt/archives/*
            elif command -v yum &>/dev/null; then
                yum clean all && dnf clean all 2>/dev/null
            fi
            rm -rf /tmp/* /var/tmp/*
            journalctl --vacuum-size=100M 2>/dev/null
            log "INFO" "✅ 系统清理完成！"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        14)
            log "INFO" "安装系统必备基础工具..."
            if command -v apt &>/dev/null; then
                apt update -y && apt install -y wget curl vim zip unzip tar make gcc git socat net-tools dnsutils htop iotop iftop mtr traceroute virt-what dmidecode bc
            elif command -v yum &>/dev/null; then
                yum install -y epel-release && yum install -y wget curl vim zip unzip tar make gcc git socat net-tools dnsutils htop iotop iftop mtr traceroute virt-what dmidecode bc
            fi
            log "INFO" "✅ 基础工具安装完成！"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        15)
            clear
            log "INFO" "========== Docker 一站式管理 =========="
            echo "【1】安装 Docker（linuxmirrors 官方脚本）"
            echo "【2】彻底卸载 Docker（清空所有数据）"
            echo "【3】更新 Docker 【4】查看状态 【5】容器操作 【6】清理无用资源"
            read -p "请选择操作：" docker_opt
            case $docker_opt in
                1)
                    log "INFO" "开始安装 Docker（国内镜像源）..."
                    bash <(curl -sSL https://linuxmirrors.cn/docker.sh)
                    log "INFO" "✅ Docker 安装完成！"
                    docker -v
                    ;;
                2)
                    log "WARN" "⚠️ 即将彻底卸载 Docker，所有镜像/容器/数据将全部删除！"
                    read -p "确定继续？(y/n)：" docker_confirm
                    if [ "$docker_confirm" = "y" ]; then
                        systemctl stop docker
                        systemctl disable docker
                        apt remove -y docker-ce docker-ce-cli containerd.io 2>/dev/null
                        yum remove -y docker-ce docker-ce-cli containerd.io 2>/dev/null
                        rm -rf /var/lib/docker /var/lib/containerd /etc/docker /run/docker
                        log "INFO" "✅ Docker 已彻底卸载清理！"
                    else
                        log "INFO" "已取消卸载"
                    fi
                    ;;
                3)
                    apt update -y && apt upgrade docker-ce docker-ce-cli containerd.io -y 2>/dev/null
                    yum update docker-ce docker-ce-cli containerd.io -y 2>/dev/null
                    systemctl restart docker
                    log "INFO" "✅ Docker 更新完成"; docker -v
                    ;;
                4)
                    systemctl status docker --no-pager
                    docker -v
                    docker-compose -v 2>/dev/null
                    ;;
                5)
                    read -p "输入容器名称/ID：" cname
                    echo "1)启动 2)停止 3)重启"
                    read -p "选择：" cact
                    [ "$cact" -eq 1 ] && docker start "$cname"
                    [ "$cact" -eq 2 ] && docker stop "$cname"
                    [ "$cact" -eq 3 ] && docker restart "$cname"
                    log "INFO" "操作完成"
                    ;;
                6)
                    docker system prune -a -f --volumes
                    log "INFO" "✅ Docker 清理完成"
                    ;;
                *) log "ERROR" "无效选项" ;;
            esac
            read -p "按回车键返回主菜单..."
            continue
            ;;
        17)
            log "INFO" "感谢使用，再见！"
            exit 0
            ;;
        1)
            # Ubuntu 网络安装
            echo "请选择 Ubuntu 版本："
            echo "1) 20.04 (Focal Fossa)"
            echo "2) 22.04 (Jammy Jellyfish)"
            echo "3) 24.04 (Noble Numbat)"
            echo "4) 26.04 (Plucky Puffin) [LTS]"
            read -p "请输入序号（1-4）：" ub_ver
            case $ub_ver in
                1) CODENAME="focal"; DISPLAY="20.04" ;;
                2) CODENAME="jammy"; DISPLAY="22.04" ;;
                3) CODENAME="noble"; DISPLAY="24.04" ;;
                4) CODENAME="plucky"; DISPLAY="26.04" ;;
                *) err_exit "无效选择" ;;
            esac
            OS_TYPE="Ubuntu"
            VERSION_CODENAME="$CODENAME"
            VERSION_DISPLAY="$DISPLAY"
            ;;
        2)
            # Debian 网络安装
            echo "请选择 Debian 版本："
            echo "1) Debian 10 (Buster)"
            echo "2) Debian 11 (Bullseye)"
            echo "3) Debian 12 (Bookworm)"
            echo "4) Debian 13 (Trixie)"
            read -p "请输入序号（1-4）：" db_ver
            case $db_ver in
                1) CODENAME="buster"; DISPLAY="10" ;;
                2) CODENAME="bullseye"; DISPLAY="11" ;;
                3) CODENAME="bookworm"; DISPLAY="12" ;;
                4) CODENAME="trixie"; DISPLAY="13" ;;
                *) err_exit "无效选择" ;;
            esac
            OS_TYPE="Debian"
            VERSION_CODENAME="$CODENAME"
            VERSION_DISPLAY="$DISPLAY"
            ;;
        3)
            # CentOS 网络安装
            echo "请选择 CentOS 版本："
            echo "1) CentOS 7"
            echo "2) CentOS 8"
            echo "3) CentOS 9 Stream"
            read -p "请输入序号（1-3）：" cs_ver
            case $cs_ver in
                1) CODENAME="7.9.2009"; DISPLAY="7" ;;
                2) CODENAME="8.5.2111"; DISPLAY="8" ;;
                3) CODENAME="9-stream"; DISPLAY="9-stream" ;;
                *) err_exit "无效选择" ;;
            esac
            OS_TYPE="CentOS"
            VERSION_CODENAME="$CODENAME"
            VERSION_DISPLAY="$DISPLAY"
            ;;
        *)
            log "ERROR" "无效的功能序号！请输入1-17"
            read -p "按回车键返回主菜单..."
            continue
            ;;
    esac

    # 对于 1-3 选项，继续执行网络安装流程
    if [[ "$main_opt" -eq 1 || "$main_opt" -eq 2 || "$main_opt" -eq 3 ]]; then
        # 密码设置
        echo -e "\n--- 系统密码设置 ---"
        log "INFO" "默认密码：$DEFAULT_PASS"
        read -p "是否修改密码？(y/n)：" change_pass
        if [[ "$change_pass" =~ ^[Yy]$ ]]; then
            while true; do
                read -p "请输入新密码（至少8位，含字母+数字）：" new_pass
                if [ ${#new_pass} -lt 8 ]; then
                    log "WARN" "密码长度不能少于8位！"
                elif ! [[ "$new_pass" =~ [a-zA-Z] && "$new_pass" =~ [0-9] ]]; then
                    log "WARN" "密码必须包含字母和数字！"
                else
                    DEFAULT_PASS=$new_pass
                    break
                fi
            done
        fi

        read -p "请输入 SSH 端口（默认22）：" ssh_port
        [ -z "$ssh_port" ] && ssh_port="22"

        echo "--- 网络配置 ---"
        read -p "使用 DHCP 自动获取 IP？(y/n, 默认 y): " use_dhcp
        use_dhcp=${use_dhcp:-y}
        static_info=""
        dns="8.8.8.8"
        if [[ "$use_dhcp" =~ ^[Nn]$ ]]; then
            read -p "请输入 IP 地址：" ip_addr
            read -p "请输入子网掩码（例如 255.255.255.0）：" ip_mask
            read -p "请输入网关地址：" ip_gate
            read -p "请输入 DNS 服务器（默认 8.8.8.8）：" dns_input
            [ -n "$dns_input" ] && dns="$dns_input"
            static_info="$ip_addr $ip_mask $ip_gate"
        else
            read -p "请输入 DNS 服务器（默认 8.8.8.8）：" dns_input
            [ -n "$dns_input" ] && dns="$dns_input"
        fi

        log "INFO" "即将执行网络安装：$OS_TYPE $VERSION_DISPLAY，密码已设置，SSH端口 $ssh_port"
        read -p "确认继续？(y/n)：" confirm
        [[ ! "$confirm" =~ ^[Yy]$ ]] && err_exit "已取消安装"

        netinstall_linux "$OS_TYPE" "$VERSION_CODENAME" "$VERSION_DISPLAY" "$DEFAULT_PASS" "$ssh_port" "$use_dhcp" "$static_info" "$dns"
        # 函数内会重启，不会返回
    fi
done
