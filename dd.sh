#!/bin/bash
#====================================================
# 全功能DD脚本 - 支持Ubuntu/Debian/CentOS全系列重装
# 支持宝塔面板 / 1Panel 面板 / Docker 一站式管理
# 默认root密码: 123456 (可修改)
# 脚本更新地址: https://raw.githubusercontent.com/sdlw7757/dd-script/main/dd.sh
#====================================================

export PATH=/usr/local/sbin:/usr/local/bin:/usr/sbin:/usr/bin:/sbin:/bin

# 颜色定义（加粗使用 \033[1m）
red='\033[0;31m'
green='\033[0;32m'
yellow='\033[0;33m'
blue='\033[0;34m'
magenta='\033[0;35m'
cyan='\033[0;36m'
bold='\033[1m'
plain='\033[0m'

# 默认配置
DEFAULT_PASSWORD="123456"
DEFAULT_SSH_PORT="22"
DEFAULT_AUTO_NET=1
DEFAULT_IPV6_ENABLE=1
DEFAULT_FIRMWARE=0

# 全局变量
ROOT_PASS="$DEFAULT_PASSWORD"
SSH_PORT="$DEFAULT_SSH_PORT"
USE_STATIC=0
STATIC_IP=""
STATIC_MASK=""
STATIC_GATE=""
STATIC_DNS="8.8.8.8"
setIPv6=0
IncFirmware=0
SELECTED_OS=""
SELECTED_VERSION=""
SELECTED_ARCH=""
VER=""
DD_MODE=0
DD_URL=""
LinuxMirror=""
myPASSWORD=""

# 脚本自身路径
SCRIPT_PATH=$(realpath "$0")

#====================================================
# 工具函数
#====================================================
_info() { echo -e "${green}[INFO]${plain} $1"; }
_warn() { echo -e "${yellow}[WARN]${plain} $1"; }
_error() { echo -e "${red}[ERROR]${plain} $1"; exit 1; }

command_exists() { command -v "$1" &>/dev/null; }

get_arch() {
    case $(uname -m) in
        aarch64|arm64) echo "arm64" ;;
        x86|i386|i686) echo "i386" ;;
        x86_64|amd64)  echo "amd64" ;;
        *) echo "" ;;
    esac
}

get_default_interface() {
    local defaultRoute=$(ip route show default | grep "^default")
    local Interfaces=$(cat /proc/net/dev | grep ':' | cut -d':' -f1 | sed 's/\s//g' | grep -iv '^lo\|^sit\|^stf\|^gif\|^dummy\|^vmnet\|^vir\|^gre\|^ipip\|^ppp\|^bond\|^tun\|^tap')
    for iface in $Interfaces; do
        echo "$defaultRoute" | grep -q "$iface" && echo "$iface" && return
    done
    echo ""
}

get_disk() {
    local disk=$(lsblk | sed 's/[[:space:]]*$//g' | grep "disk$" | cut -d' ' -f1 | grep -v "fd[0-9]*\|sr[0-9]*" | head -n1)
    [ -z "$disk" ] && echo "" && return
    echo "$disk" | grep -q "/dev" && echo "$disk" || echo "/dev/$disk"
}

get_grub() {
    local boot="${1:-/boot}"
    local folder=$(find "$boot" -type d -name "grub*" 2>/dev/null | head -n1)
    [ -z "$folder" ] && return
    local fileName=$(ls -1 "$folder" 2>/dev/null | grep '^grub.conf$\|^grub.cfg$')
    if [ -z "$fileName" ]; then
        ls -1 "$folder" 2>/dev/null | grep -q '^grubenv$' || return
        folder=$(find "$boot" -type f -name "grubenv" 2>/dev/null | xargs dirname | grep -v "^$folder" | head -n1)
        [ -z "$folder" ] && return
        fileName=$(ls -1 "$folder" 2>/dev/null | grep '^grub.conf$\|^grub.cfg$')
    fi
    [ -z "$fileName" ] && return
    local ver=0
    [ "$fileName" == "grub.cfg" ] && ver=0 || ver=1
    echo "${folder}:${fileName}:${ver}"
}

select_mirror() {
    local relese=$(echo "$1" | tr '[:upper:]' '[:lower:]')
    local dist="$2"
    local arch="$3"
    local custom="$4"
    local temp_path=""
    if [ "$relese" = "debian" ] || [ "$relese" = "ubuntu" ]; then
        [ "$dist" = "focal" ] && local legacy="legacy-" || local legacy=""
        temp_path="dists/${dist}/main/installer-${arch}/current/${legacy}images/netboot/${relese}-installer/${arch}/initrd.gz"
    elif [ "$relese" = "centos" ]; then
        temp_path="${dist}/os/${arch}/isolinux/initrd.img"
    else
        return 1
    fi
    local mirrors=(
        "https://mirrors.tuna.tsinghua.edu.cn/${relese}"
        "https://mirrors.ustc.edu.cn/${relese}"
        "http://deb.debian.org/debian"
        "http://archive.ubuntu.com/ubuntu"
        "http://mirror.centos.org/centos"
    )
    [ -n "$custom" ] && mirrors=("$custom" "${mirrors[@]}")
    for base in "${mirrors[@]}"; do
        if wget --no-check-certificate --spider --timeout=3 -q "${base}/${temp_path}" 2>/dev/null; then
            echo "$base"
            return 0
        fi
    done
    return 1
}

check_depends() {
    local deps="wget,awk,grep,sed,cut,cat,lsblk,cpio,gzip,find,dirname,basename,openssl,file"
    _info "检查依赖工具..."
    for bin in $(echo "$deps" | tr ',' '\n'); do
        if ! command_exists "$bin"; then
            _error "缺少依赖: $bin，请先安装 (apt install -y $bin 或 yum install -y $bin)"
        fi
    done
    _info "依赖检查通过"
}

set_static_ip() {
    echo -e "${cyan}请输入静态 IP 地址:${plain}"
    read -r STATIC_IP
    echo -e "${cyan}请输入子网掩码 (如 255.255.255.0):${plain}"
    read -r STATIC_MASK
    echo -e "${cyan}请输入网关地址:${plain}"
    read -r STATIC_GATE
    echo -e "${cyan}请输入 DNS (默认 8.8.8.8):${plain}"
    read -r STATIC_DNS
    [ -z "$STATIC_DNS" ] && STATIC_DNS="8.8.8.8"
    USE_STATIC=1
    _info "静态网络配置完成"
}

set_install_options() {
    echo -e "${cyan}按 0 返回主菜单，其他任意键继续设置${plain}"
    read -r back_opt
    if [ "$back_opt" = "0" ]; then
        return 1
    fi
    
    echo -e "${cyan}设置 root 密码 (默认 $DEFAULT_PASSWORD，直接回车保留):${plain}"
    read -r newpass
    [ -n "$newpass" ] && ROOT_PASS="$newpass"
    echo -e "${cyan}设置 SSH 端口 (默认 $DEFAULT_SSH_PORT):${plain}"
    read -r newport
    [ -n "$newport" ] && SSH_PORT="$newport"
    echo -e "${cyan}网络模式: 1) DHCP (默认)  2) 静态IP${plain}"
    read -r netmode
    if [ "$netmode" = "2" ]; then
        set_static_ip
    else
        USE_STATIC=0
        _info "使用 DHCP"
    fi
    echo -e "${cyan}是否禁用 IPv6? (y/N):${plain}"
    read -r ipv6opt
    [[ "$ipv6opt" =~ [Yy] ]] && setIPv6=1 || setIPv6=0
    echo -e "${cyan}Debian 是否加载非自由固件? (y/N):${plain}"
    read -r fwopt
    [[ "$fwopt" =~ [Yy] ]] && IncFirmware=1 || IncFirmware=0
    _info "安装选项已保存"
    return 0
}

#====================================================
# DD 安装核心
#====================================================
prepare_install_files() {
    local os_lower=$(echo "$SELECTED_OS" | tr '[:upper:]' '[:lower:]')
    local mirror=""
    local dist="$SELECTED_VERSION"
    local arch="$SELECTED_ARCH"
    if [ "$SELECTED_OS" = "CentOS" ]; then
        mirror=$(select_mirror "CentOS" "$dist" "$arch" "")
        [ -z "$mirror" ] && _error "无法找到 CentOS $dist 的镜像源"
        LinuxMirror="$mirror"
        _info "下载 CentOS 安装内核..."
        wget --no-check-certificate -qO /tmp/initrd.img "${mirror}/${dist}/os/${arch}/isolinux/initrd.img" || _error "下载 initrd.img 失败"
        wget --no-check-certificate -qO /tmp/vmlinuz "${mirror}/${dist}/os/${arch}/isolinux/vmlinuz" || _error "下载 vmlinuz 失败"
    else
        mirror=$(select_mirror "$SELECTED_OS" "$dist" "$arch" "")
        [ -z "$mirror" ] && _error "无法找到 ${SELECTED_OS} ${dist} 的镜像源"
        LinuxMirror="$mirror"
        _info "下载 ${SELECTED_OS} 安装内核..."
        local legacy=""
        [ "$dist" = "focal" ] && legacy="legacy-"
        wget --no-check-certificate -qO /tmp/initrd.img "${mirror}/dists/${dist}/main/installer-${arch}/current/${legacy}images/netboot/${os_lower}-installer/${arch}/initrd.gz" || _error "下载 initrd.img 失败"
        wget --no-check-certificate -qO /tmp/vmlinuz "${mirror}/dists/${dist}/main/installer-${arch}/current/${legacy}images/netboot/${os_lower}-installer/${arch}/linux" || _error "下载 vmlinuz 失败"
    fi
    if [ "$IncFirmware" = "1" ] && [ "$SELECTED_OS" = "Debian" ]; then
        wget --no-check-certificate -qO /tmp/firmware.cpio.gz "http://cdimage.debian.org/cdimage/unofficial/non-free/firmware/${dist}/current/firmware.cpio.gz" && _info "已下载附加固件"
    fi
}

generate_preseed_cfg() {
    local os_lower=$(echo "$SELECTED_OS" | tr '[:upper:]' '[:lower:]')
    local mirror_host=$(echo "$LinuxMirror" | awk -F'://|/' '{print $2}')
    local mirror_dir=$(echo "$LinuxMirror" | awk -F"$mirror_host" '{print $2}')
    [ -z "$mirror_dir" ] && mirror_dir="/"
    local disk=$(get_disk)
    [ -z "$disk" ] && _error "未找到磁盘设备"
    
    local ip_cfg=""
    if [ "$USE_STATIC" -eq 1 ]; then
        ip_cfg="d-i netcfg/disable_autoconfig boolean true
d-i netcfg/dhcp_failed note
d-i netcfg/dhcp_options select Configure network manually
d-i netcfg/get_ipaddress string $STATIC_IP
d-i netcfg/get_netmask string $STATIC_MASK
d-i netcfg/get_gateway string $STATIC_GATE
d-i netcfg/get_nameservers string $STATIC_DNS
d-i netcfg/confirm_static boolean true"
    else
        ip_cfg="d-i netcfg/disable_autoconfig boolean false
d-i netcfg/dhcp_options select Use DHCP"
    fi
    local interface_name=$(get_default_interface)
    [ -z "$interface_name" ] && interface_name="auto"
    
    cat > /tmp/preseed.cfg <<EOF
d-i debian-installer/locale string en_US.UTF-8
d-i debian-installer/country string US
d-i debian-installer/language string en
d-i console-setup/layoutcode string us
d-i keyboard-configuration/xkb-keymap string us
d-i netcfg/choose_interface select $interface_name
$ip_cfg
d-i hw-detect/load_firmware boolean true
d-i mirror/country string manual
d-i mirror/http/hostname string $mirror_host
d-i mirror/http/directory string $mirror_dir
d-i mirror/http/proxy string
d-i passwd/root-login boolean true
d-i passwd/make-user boolean false
d-i passwd/root-password-crypted password $myPASSWORD
d-i user-setup/allow-password-weak boolean true
d-i clock-setup/utc boolean true
d-i time/zone string UTC
d-i clock-setup/ntp boolean false
d-i partman-auto/method string regular
d-i partman-auto/choose_recipe select All files in one partition (recommended for new users)
d-i partman/confirm_write_new_label boolean true
d-i partman/choose_partition select finish
d-i partman/confirm boolean true
d-i partman/confirm_nooverwrite boolean true
d-i debian-installer/allow_unauthenticated boolean true
tasksel tasksel/first multiselect minimal
d-i pkgsel/include string openssh-server
d-i pkgsel/upgrade select none
d-i apt-setup/services-select multiselect
popularity-contest popularity-contest/participate boolean false
d-i grub-installer/only_debian boolean true
d-i grub-installer/bootdev string $disk
d-i finish-install/reboot_in_progress note
d-i debian-installer/exit/reboot boolean true
d-i preseed/late_command string \
sed -ri 's/^#?Port.*/Port ${SSH_PORT}/g' /target/etc/ssh/sshd_config; \
sed -ri 's/^#?PermitRootLogin.*/PermitRootLogin yes/g' /target/etc/ssh/sshd_config; \
sed -ri 's/^#?PasswordAuthentication.*/PasswordAuthentication yes/g' /target/etc/ssh/sshd_config;
EOF
    [ "$SELECTED_OS" != "Ubuntu" ] && sed -i '/d-i user-setup\/allow-password-weak/d' /tmp/preseed.cfg
    _info "Preseed 配置文件已生成"
}

generate_ks_cfg() {
    local disk=$(get_disk)
    [ -z "$disk" ] && _error "未找到磁盘设备"
    local ip_line=""
    if [ "$USE_STATIC" -eq 1 ]; then
        ip_line="network --bootproto=static --ip=$STATIC_IP --netmask=$STATIC_MASK --gateway=$STATIC_GATE --nameserver=$STATIC_DNS --onboot=on"
    else
        ip_line="network --bootproto=dhcp --onboot=on"
    fi
    cat > /tmp/ks.cfg <<EOF
install
url --url="$LinuxMirror/${SELECTED_VERSION}/os/$SELECTED_ARCH/"
rootpw --iscrypted $myPASSWORD
auth --useshadow --passalgo=sha512
firstboot --disable
lang en_US
keyboard us
selinux --disabled
logging --level=info
reboot
text
timezone --isUtc UTC
$ip_line
bootloader --location=mbr
zerombr
clearpart --all --initlabel
autopart
%packages
@base
openssh-server
%end
%post
systemctl enable sshd
%end
EOF
    _info "Kickstart 配置文件已生成"
}

pack_initrd() {
    _info "打包 initrd.img ..."
    mkdir -p /tmp/initrd_unpack
    cd /tmp/initrd_unpack
    local comp_type=$(file /tmp/initrd.img | grep -o 'gzip compressed\|XZ compressed\|LZMA compressed' | head -n1)
    if echo "$comp_type" | grep -qi "gzip"; then
        gunzip -c /tmp/initrd.img | cpio -idm
    elif echo "$comp_type" | grep -qi "XZ"; then
        xz -dc /tmp/initrd.img | cpio -idm
    elif echo "$comp_type" | grep -qi "LZMA"; then
        lzma -dc /tmp/initrd.img | cpio -idm
    else
        _error "未知的 initrd 压缩格式"
    fi
    if [ "$SELECTED_OS" = "CentOS" ]; then
        cp /tmp/ks.cfg ./ks.cfg
    else
        cp /tmp/preseed.cfg ./preseed.cfg
    fi
    find . | cpio -H newc -o | gzip -9 > /tmp/initrd_new.img
    mv /tmp/initrd_new.img /tmp/initrd.img
    cd /
    rm -rf /tmp/initrd_unpack
    _info "initrd.img 打包完成"
}

start_installation() {
    cp -f /tmp/vmlinuz /boot/vmlinuz_install
    cp -f /tmp/initrd.img /boot/initrd.img_install
    local grub_info=$(get_grub "/boot")
    [ -z "$grub_info" ] && _error "无法找到 GRUB 配置"
    local grubdir=$(echo "$grub_info" | cut -d':' -f1)
    local grubfile=$(echo "$grub_info" | cut -d':' -f2)
    local grubver=$(echo "$grub_info" | cut -d':' -f3)
    cp "$grubdir/$grubfile" "$grubdir/$grubfile.bak"
    local boot_opt=""
    if [ "$SELECTED_OS" = "CentOS" ]; then
        boot_opt="ks=file://ks.cfg ksdevice=link"
    else
        boot_opt="auto=true hostname=install domain= quiet"
        [ "$USE_STATIC" -eq 1 ] && boot_opt="$boot_opt netcfg/disable_autoconfig=true"
    fi
    [ "$setIPv6" -eq 1 ] && boot_opt="$boot_opt ipv6.disable=1"
    
    local new_entry=""
    if [ "$grubver" = "0" ]; then
        new_entry="menuentry 'Install OS [${SELECTED_VERSION} ${SELECTED_ARCH}]' {
    linux /boot/vmlinuz_install $boot_opt
    initrd /boot/initrd.img_install
}"
    else
        new_entry="title Install OS [${SELECTED_VERSION} ${SELECTED_ARCH}]
    kernel /boot/vmlinuz_install $boot_opt
    initrd /boot/initrd.img_install"
    fi
    sed -i "1i${new_entry}\n" "$grubdir/$grubfile"
    sed -i 's/saved_entry/#saved_entry/g' "$grubdir/grubenv" 2>/dev/null
    _info "系统将在 3 秒后重启并开始安装..."
    sleep 3
    reboot
}

install_os() {
    myPASSWORD=$(openssl passwd -1 "$ROOT_PASS")
    [ -z "$SELECTED_OS" ] || [ -z "$SELECTED_VERSION" ] || [ -z "$SELECTED_ARCH" ] && _error "请先选择操作系统和版本"
    prepare_install_files
    if [ "$SELECTED_OS" = "CentOS" ]; then
        generate_ks_cfg
    else
        generate_preseed_cfg
    fi
    pack_initrd
    start_installation
}

#====================================================
# DD 菜单：选择具体版本（含返回主菜单）
#====================================================
menu_ubuntu() {
    echo -e "${cyan}请选择 Ubuntu 版本:${plain}"
    echo "1) Ubuntu 20.04 (focal)  2) Ubuntu 18.04 (bionic)  3) Ubuntu 22.04 (jammy)  4) Ubuntu 24.04 (noble)  0) 返回主菜单"
    read -r opt
    case $opt in
        1) SELECTED_VERSION="focal" ;;
        2) SELECTED_VERSION="bionic" ;;
        3) SELECTED_VERSION="jammy" ;;
        4) SELECTED_VERSION="noble" ;;
        0) return ;;
        *) SELECTED_VERSION="jammy" ;;
    esac
    SELECTED_OS="Ubuntu"
    SELECTED_ARCH=$(get_arch)
    [[ "$SELECTED_ARCH" = "amd64" ]] || [[ "$SELECTED_ARCH" = "i386" ]] || SELECTED_ARCH="amd64"
    _info "已选择 Ubuntu $SELECTED_VERSION ($SELECTED_ARCH)"
    set_install_options
    if [ $? -eq 1 ]; then
        return
    fi
    echo -e "${cyan}是否立即开始安装？(y/N)${plain}"
    read -r confirm
    [[ "$confirm" =~ [Yy] ]] && install_os
}

menu_debian() {
    echo -e "${cyan}请选择 Debian 版本:${plain}"
    echo "1) Debian 11 (bullseye)  2) Debian 10 (buster)  3) Debian 12 (bookworm)  0) 返回主菜单"
    read -r opt
    case $opt in
        1) SELECTED_VERSION="bullseye" ;;
        2) SELECTED_VERSION="buster" ;;
        3) SELECTED_VERSION="bookworm" ;;
        0) return ;;
        *) SELECTED_VERSION="bullseye" ;;
    esac
    SELECTED_OS="Debian"
    SELECTED_ARCH=$(get_arch)
    [[ "$SELECTED_ARCH" = "amd64" ]] || [[ "$SELECTED_ARCH" = "i386" ]] || SELECTED_ARCH="amd64"
    _info "已选择 Debian $SELECTED_VERSION ($SELECTED_ARCH)"
    set_install_options
    if [ $? -eq 1 ]; then
        return
    fi
    echo -e "${cyan}是否立即开始安装？(y/N)${plain}"
    read -r confirm
    [[ "$confirm" =~ [Yy] ]] && install_os
}

menu_centos() {
    echo -e "${cyan}请选择 CentOS 版本:${plain}"
    echo "1) CentOS 7.9  2) CentOS 6.10  3) CentOS 8.5 (stream)  0) 返回主菜单"
    read -r opt
    case $opt in
        1) SELECTED_VERSION="7.9.2009" ;;
        2) SELECTED_VERSION="6.10" ;;
        3) SELECTED_VERSION="8.5.2111" ;;
        0) return ;;
        *) SELECTED_VERSION="7.9.2009" ;;
    esac
    SELECTED_OS="CentOS"
    SELECTED_ARCH="x86_64"
    _info "已选择 CentOS $SELECTED_VERSION ($SELECTED_ARCH)"
    set_install_options
    if [ $? -eq 1 ]; then
        return
    fi
    echo -e "${cyan}是否立即开始安装？(y/N)${plain}"
    read -r confirm
    [[ "$confirm" =~ [Yy] ]] && install_os
}

#====================================================
# 面板管理函数
#====================================================
install_bt() {
    _info "开始安装宝塔面板 (官方脚本)..."
    if command_exists bt; then
        _warn "宝塔面板已安装，如需重装请先执行清理"
        return
    fi
    if command_exists curl; then
        curl -sSO https://download.bt.cn/install/install_panel.sh
    else
        wget -O install_panel.sh https://download.bt.cn/install/install_panel.sh
    fi
    bash install_panel.sh ed8484bec
}

repair_bt() {
    _info "尝试修复宝塔面板..."
    if command_exists bt; then
        bt 16
        bt 1
        _info "宝塔面板修复完成"
    else
        _warn "宝塔面板未安装，请先安装"
    fi
}

clean_bt() {
    _warn "即将卸载宝塔面板并清理所有数据 (不可恢复)"
    echo -e "${cyan}确认继续? (y/N)${plain}"
    read -r confirm
    if [[ "$confirm" =~ [Yy] ]]; then
        if command_exists bt; then
            bt 11
            bt 12
            service bt stop
            chkconfig --del bt
        fi
        curl -sSO http://download.bt.cn/install/bt-uninstall.sh && bash bt-uninstall.sh
        rm -rf /www/server/panel
        _info "宝塔面板已卸载"
    else
        _info "操作取消"
    fi
}

install_1panel() {
    _info "开始安装 1Panel 面板..."
    if command_exists 1panel; then
        _warn "1Panel 已安装，如需重装请先执行清理"
        return
    fi
    curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && bash quick_start.sh
}

repair_1panel() {
    _info "尝试修复 1Panel..."
    if command_exists 1panel; then
        1panel update
        _info "1Panel 已更新到最新版"
    else
        _warn "1Panel 未安装，请先安装"
    fi
}

clean_1panel() {
    _warn "即将卸载 1Panel (数据不可恢复)"
    echo -e "${cyan}确认继续? (y/N)${plain}"
    read -r confirm
    if [[ "$confirm" =~ [Yy] ]]; then
        curl -sSL https://resource.fit2cloud.com/1panel/package/quick_start.sh -o quick_start.sh && bash quick_start.sh --uninstall
        rm -rf /opt/1panel
        _info "1Panel 已卸载"
    else
        _info "操作取消"
    fi
}

panel_bt_menu() {
    clear
    echo -e "${cyan}========== 宝塔面板管理 ==========${plain}"
    echo " 1) 安装宝塔面板"
    echo " 2) 修复宝塔面板"
    echo " 3) 清理/卸载宝塔面板"
    echo " 0) 返回主菜单"
    read -r opt
    case $opt in
        1) install_bt ;;
        2) repair_bt ;;
        3) clean_bt ;;
        0) return ;;
        *) _warn "无效输入" ;;
    esac
    echo -e "${cyan}按 Enter 返回面板菜单${plain}"
    read -r
    panel_bt_menu
}

panel_1panel_menu() {
    clear
    echo -e "${cyan}========== 1Panel 面板管理 ==========${plain}"
    echo " 1) 安装 1Panel"
    echo " 2) 修复/更新 1Panel"
    echo " 3) 清理/卸载 1Panel"
    echo " 0) 返回主菜单"
    read -r opt
    case $opt in
        1) install_1panel ;;
        2) repair_1panel ;;
        3) clean_1panel ;;
        0) return ;;
        *) _warn "无效输入" ;;
    esac
    echo -e "${cyan}按 Enter 返回面板菜单${plain}"
    read -r
    panel_1panel_menu
}

#====================================================
# Docker 一站式管理子菜单
#====================================================
docker_install() {
    _info "开始安装 Docker..."
    if command -v docker &>/dev/null; then
        _warn "Docker 已安装，如需重装请先卸载"
        return
    fi
    curl -fsSL https://get.docker.com | bash
    if [ $? -eq 0 ]; then
        systemctl enable docker && systemctl start docker
        _info "Docker 安装成功"
    else
        _error "Docker 安装失败"
    fi
}

docker_uninstall() {
    _warn "即将卸载 Docker (保留容器数据，如需完全删除请手动删除 /var/lib/docker)"
    echo -e "${cyan}确认继续? (y/N)${plain}"
    read -r confirm
    [[ ! "$confirm" =~ [Yy] ]] && _info "操作取消" && return
    if command -v apt &>/dev/null; then
        apt purge -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    elif command -v yum &>/dev/null; then
        yum remove -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    else
        _error "不支持的系统"
    fi
    rm -rf /var/lib/docker /var/lib/containerd
    _info "Docker 已卸载"
}

docker_update() {
    _info "开始更新 Docker..."
    if ! command -v docker &>/dev/null; then
        _warn "Docker 未安装，将执行安装"
        docker_install
        return
    fi
    curl -fsSL https://get.docker.com | bash
    _info "Docker 已更新到最新版"
    systemctl restart docker
}

container_menu() {
    while true; do
        clear
        echo -e "${cyan}========== 容器管理 ==========${plain}"
        echo -e "${green}1) 查看所有容器${plain}"
        echo -e "${green}2) 启动容器${plain}"
        echo -e "${green}3) 停止容器${plain}"
        echo -e "${green}4) 重启容器${plain}"
        echo -e "${green}5) 删除容器${plain}"
        echo -e "${green}0) 返回上级菜单${plain}"
        read -r opt
        case $opt in
            1)
                echo -e "${cyan}当前所有容器（含已停止）：${plain}"
                docker ps -a
                echo -e "${cyan}按 Enter 继续${plain}"
                read -r
                ;;
            2)
                read -r -p "请输入要启动的容器名称或ID: " cid
                docker start "$cid" && _info "容器 $cid 已启动" || _warn "启动失败"
                read -r -p "按 Enter 继续" 
                ;;
            3)
                read -r -p "请输入要停止的容器名称或ID: " cid
                docker stop "$cid" && _info "容器 $cid 已停止" || _warn "停止失败"
                read -r -p "按 Enter 继续"
                ;;
            4)
                read -r -p "请输入要重启的容器名称或ID: " cid
                docker restart "$cid" && _info "容器 $cid 已重启" || _warn "重启失败"
                read -r -p "按 Enter 继续"
                ;;
            5)
                read -r -p "请输入要删除的容器名称或ID: " cid
                docker rm "$cid" && _info "容器 $cid 已删除" || _warn "删除失败"
                read -r -p "按 Enter 继续"
                ;;
            0) return ;;
            *) _warn "无效输入" ;;
        esac
    done
}

docker_menu() {
    while true; do
        clear
        echo -e "${cyan}========== Docker 一站式管理 ==========${plain}"
        echo -e "${green}1) 安装 Docker${plain}"
        echo -e "${green}2) 卸载 Docker${plain}"
        echo -e "${green}3) 更新 Docker${plain}"
        echo -e "${green}4) 容器管理${plain}"
        echo -e "${green}0) 返回主菜单${plain}"
        read -r opt
        case $opt in
            1) docker_install ;;
            2) docker_uninstall ;;
            3) docker_update ;;
            4) container_menu ;;
            0) return ;;
            *) _warn "无效输入" ;;
        esac
        echo -e "${cyan}按 Enter 返回 Docker 菜单${plain}"
        read -r
    done
}

#====================================================
# 系统信息查询（修复CPU和内存显示）
#====================================================
system_info() {
    clear
    echo -e "${bold}${cyan}========== 系统信息 ==========${plain}"
    echo -e "${green}主机名:${plain} $(hostname)"
    echo -e "${green}系统版本:${plain} $(cat /etc/os-release | grep PRETTY_NAME | cut -d'"' -f2)"
    echo -e "${green}内核版本:${plain} $(uname -r)"
    echo -e "${green}架构:${plain} $(uname -m)"
    
    # 获取 CPU 型号（兼容多种方式）
    CPU_MODEL=$(cat /proc/cpuinfo | grep "model name" | head -1 | cut -d':' -f2 | xargs)
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL=$(lscpu | grep "Model name" | cut -d':' -f2 | xargs)
    fi
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL=$(lscpu | grep "CPU name" | cut -d':' -f2 | xargs)
    fi
    if [ -z "$CPU_MODEL" ]; then
        CPU_MODEL="未知"
    fi
    echo -e "${green}CPU 型号:${plain} $CPU_MODEL"
    
    echo -e "${green}CPU 核心数:${plain} $(nproc)"
    
    # 获取内存信息（兼容 free 输出格式）
    MEM_TOTAL=$(free -h | awk '/^Mem:/ {print $2}')
    if [ -z "$MEM_TOTAL" ]; then
        MEM_TOTAL=$(free -h | awk '/^Mem/ {print $2}')
    fi
    MEM_USED=$(free -h | awk '/^Mem:/ {print $3}')
    if [ -z "$MEM_USED" ]; then
        MEM_USED=$(free -h | awk '/^Mem/ {print $3}')
    fi
    MEM_AVAIL=$(free -h | awk '/^Mem:/ {print $4}')
    if [ -z "$MEM_AVAIL" ]; then
        MEM_AVAIL=$(free -h | awk '/^Mem/ {print $4}')
    fi
    echo -e "${green}内存总大小:${plain} ${MEM_TOTAL:-未知}"
    echo -e "${green}已用内存:${plain} ${MEM_USED:-未知}"
    echo -e "${green}可用内存:${plain} ${MEM_AVAIL:-未知}"
    
    echo -e "${green}硬盘使用情况:${plain}"
    df -h | grep -E '^/dev/'
    echo -e "${green}系统负载:${plain} $(uptime | awk -F'load average:' '{print $2}')"
    echo -e "${green}当前用户:${plain} $(whoami)"
    echo -e "${green}已登录用户:${plain}"
    who
    echo -e "${cyan}按 Enter 返回主菜单${plain}"
    read -r
}

#====================================================
# 系统更新（自动优先使用国内源，含 Git 安装）
#====================================================
system_update() {
    _info "开始系统更新 (将优先使用国内镜像源)..."
    
    # 备份并更换国内源
    if command -v apt &>/dev/null; then
        # Debian / Ubuntu
        if [ ! -f /etc/apt/sources.list.bak ]; then
            cp /etc/apt/sources.list /etc/apt/sources.list.bak
            _info "已备份原软件源到 /etc/apt/sources.list.bak"
        fi
        # 获取发行版名称和代号
        if grep -qi "ubuntu" /etc/os-release; then
            CODENAME=$(lsb_release -sc 2>/dev/null)
            if [ -n "$CODENAME" ]; then
                cat > /etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME-updates main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME-backports main restricted universe multiverse
deb https://mirrors.tuna.tsinghua.edu.cn/ubuntu/ $CODENAME-security main restricted universe multiverse
EOF
                _info "已更换为清华源 (Ubuntu $CODENAME)"
            else
                _warn "无法获取 Ubuntu 版本代号，跳过换源"
            fi
        else
            # Debian
            CODENAME=$(lsb_release -sc 2>/dev/null)
            if [ -n "$CODENAME" ]; then
                cat > /etc/apt/sources.list <<EOF
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian/ $CODENAME-updates main contrib non-free non-free-firmware
deb https://mirrors.tuna.tsinghua.edu.cn/debian-security $CODENAME-security main contrib non-free non-free-firmware
EOF
                _info "已更换为清华源 (Debian $CODENAME)"
            else
                _warn "无法获取 Debian 版本代号，跳过换源"
            fi
        fi
        apt update
        apt upgrade -y
        _info "正在安装/更新 Git..."
        apt install -y git
    elif command -v yum &>/dev/null; then
        # CentOS / RHEL
        if grep -qi "release 7" /etc/centos-release 2>/dev/null; then
            if [ ! -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
                cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak 2>/dev/null
                _info "已备份原 yum 源"
            fi
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-7.repo
            _info "已更换为阿里云 CentOS 7 源"
        elif grep -qi "release 8" /etc/centos-release 2>/dev/null; then
            if [ ! -f /etc/yum.repos.d/CentOS-Base.repo.bak ]; then
                cp /etc/yum.repos.d/CentOS-Base.repo /etc/yum.repos.d/CentOS-Base.repo.bak 2>/dev/null
            fi
            curl -o /etc/yum.repos.d/CentOS-Base.repo https://mirrors.aliyun.com/repo/Centos-8.repo
            _info "已更换为阿里云 CentOS 8 源"
        else
            _warn "不支持的 CentOS 版本，跳过换源"
        fi
        yum makecache
        yum update -y
        _info "正在安装/更新 Git..."
        yum install -y git
    else
        _error "不支持的系统包管理器"
    fi
    _info "系统更新及 Git 安装完成"
    echo -e "${cyan}按 Enter 返回主菜单${plain}"
    read -r
}

#====================================================
# 系统清理（安全清理）
#====================================================
system_clean() {
    _warn "即将执行系统清理（清理包缓存、旧日志、/tmp 临时文件）"
    echo -e "${cyan}确认继续? (y/N)${plain}"
    read -r confirm
    [[ ! "$confirm" =~ [Yy] ]] && _info "操作取消" && return
    if command -v apt &>/dev/null; then
        apt autoremove -y
        apt autoclean
        apt clean
    elif command -v yum &>/dev/null; then
        yum autoremove -y
        yum clean all
    fi
    # 清理日志文件（保留最近3天）
    find /var/log -type f -name "*.log" -mtime +3 -exec truncate -s 0 {} \; 2>/dev/null
    # 清理 /tmp 下超过3天的文件
    find /tmp -type f -atime +3 -delete 2>/dev/null
    _info "系统清理完成"
    echo -e "${cyan}按 Enter 返回主菜单${plain}"
    read -r
}

#====================================================
# 脚本更新（使用 GitHub 地址）
#====================================================
update_script() {
    _info "正在检查脚本更新..."
    local tmp_path="/tmp/dd_install_new.sh"
    local remote_url="https://raw.githubusercontent.com/sdlw7757/dd-script/main/dd.sh"
    if wget --no-check-certificate -qO "$tmp_path" "$remote_url"; then
        sed -i 's/\r$//' "$tmp_path"
        cp "$tmp_path" "$SCRIPT_PATH"
        chmod +x "$SCRIPT_PATH"
        _info "脚本已更新，请重新运行"
        exit 0
    else
        _warn "检查更新失败，请检查网络或手动从 GitHub 下载最新脚本"
        _warn "手动更新命令: wget -O $SCRIPT_PATH $remote_url && sed -i 's/\\r\$//' $SCRIPT_PATH"
        echo -e "${cyan}按 Enter 返回主菜单${plain}"
        read -r
        return 1
    fi
}

#====================================================
# 主菜单（加粗、增大文字）
#====================================================
show_main_menu() {
    clear
    echo -e "${bold}${cyan}============================================================${plain}"
    echo -e "${bold}${cyan}==================== 全功能DD脚本主菜单 ====================${plain}"
    echo -e "${bold}${cyan}============================================================${plain}"
    echo ""
    echo -e "${bold}${green}【1】${plain} Ubuntu 全系列版本 DD重装"
    echo -e "${bold}${green}【2】${plain} Debian 全系列版本 DD重装"
    echo -e "${bold}${green}【3】${plain} CentOS 全系列版本 DD重装"
    echo -e "${bold}${green}【4】${plain} 一键安装/修复/清理 宝塔面板"
    echo -e "${bold}${green}【5】${plain} 一键安装/修复/清理 1Panel面板"
    echo -e "${bold}${green}【6】${plain} Docker 一站式管理（安装/卸载/更新/容器）"
    echo -e "${bold}${green}【7】${plain} 系统信息查询"
    echo -e "${bold}${green}【8】${plain} 系统更新（自动国内源，含 Git）"
    echo -e "${bold}${green}【9】${plain} 系统清理"
    echo ""
    echo -e " ------------------------"
    echo -e "  ${bold}${yellow}00.${plain}  脚本更新"
    echo -e " ------------------------"
    echo -e "  ${bold}${yellow}0.${plain}   退出脚本"
    echo -e " ---------------------------------------------------------------"
    echo -e " ${bold}${green}提示：在菜单中按 y 可快速重启本脚本（刷新菜单）${plain}"
    echo -e "${bold}${cyan}============================================================${plain}"
}

#====================================================
# 主程序
#====================================================
main() {
    [ "$EUID" -ne 0 ] && _error "请以 root 权限运行此脚本"
    VER=$(get_arch)
    [ -z "$VER" ] && _error "不支持的 CPU 架构"
    check_depends
    
    while true; do
        show_main_menu
        read -r choice
        case $choice in
            1) menu_ubuntu ;;
            2) menu_debian ;;
            3) menu_centos ;;
            4) panel_bt_menu ;;
            5) panel_1panel_menu ;;
            6) docker_menu ;;
            7) system_info ;;
            8) system_update ;;
            9) system_clean ;;
            00) update_script ;;
            0) _info "已退出脚本"; exit 0 ;;
            y|Y) 
                _info "重新启动脚本..."
                sleep 1
                exec "$0" "$@"
                ;;
            *) _warn "无效输入，请重新选择"; sleep 1 ;;
        esac
    done
}

main "$@"
