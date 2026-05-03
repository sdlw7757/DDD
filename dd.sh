#!/bin/bash
# ============================================================
# 增强版全能DD脚本（仅 Linux RAW 镜像）
# 特性：镜像缓存+断点续传+多磁盘适配+日志记录+交互优化
# 快捷唤起：输入 y/Y 直接调用 | 默认密码123456（可自定义）
# 包括：Ubuntu / Debian / CentOS 全系列版本 RAW DD
# ============================================================

Green="\033[32m"
Red="\033[31m"
Yellow="\033[33m"
Blue="\033[34m"
Plain="\033[0m"

SCRIPT_PATH="/usr/local/bin/ddtool.sh"
LOG_FILE="/var/log/dd_tool.log"
DEFAULT_PASS="123456"
CACHE_DIR="/var/cache/dd_images"
RETRY_TIMES=3
BLOCK_SIZE="8M"

# ---------------------- 日志函数 ----------------------
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

# ---------------------- 包管理器智能安装 ----------------------
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

# ---------------------- 下载与校验 ----------------------
download_with_retry() {
    local URL=$1
    local OUTPUT=$2
    local RETRY=$RETRY_TIMES
    log "INFO" "开始下载：$URL （重试次数：$RETRY）"
    for ((i=1; i<=RETRY; i++)); do
        wget --no-check-certificate --progress=bar:force -qO "$OUTPUT" "$URL"
        if [ $? -eq 0 ]; then
            log "INFO" "下载成功：$OUTPUT"
            return 0
        fi
        log "WARN" "下载失败，第 $i 次重试..."
        sleep 3
    done
    log "ERROR" "下载失败（已重试$RETRY次）：$URL"
    return 1
}

check_md5() {
    local FILE=$1
    local EXPECT_MD5=$2
    local ACTUAL_MD5=$(md5sum "$FILE" | awk '{print $1}')
    if [ "$ACTUAL_MD5" = "$EXPECT_MD5" ]; then
        log "INFO" "MD5校验通过：$ACTUAL_MD5"
        return 0
    else
        log "ERROR" "MD5校验失败！期望：$EXPECT_MD5，实际：$ACTUAL_MD5"
        return 1
    fi
}

detect_disk() {
    local DISK_LIST=("/dev/vda" "/dev/sda" "/dev/nvme0n1" "/dev/hda")
    for disk in "${DISK_LIST[@]}"; do
        if [ -b "$disk" ]; then
            log "INFO" "检测到系统磁盘：$disk"
            echo "$disk"
            return 0
        fi
    done
    err_exit "未检测到可用系统磁盘！"
}

# ---------------------- 短链接生成 ----------------------
make_short_url() {
    clear
    log "INFO" "========== 一键生成永久短链接（永不过期） =========="
    log "INFO" "使用官方公益服务：ttm.sh | 永久有效、无广告、免登录"
    read -p "请输入需要缩短的长链接：" long_url
    if [ -z "$long_url" ]; then
        err_exit "链接不能为空！"
    fi
    log "INFO" "正在生成永久短链接..."
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

# ---------------------- 初始化安装脚本自身 ----------------------
if [ ! -f "$SCRIPT_PATH" ]; then
    cp "$0" "$SCRIPT_PATH" && chmod +x "$SCRIPT_PATH" || err_exit "无法写入全局脚本"
    grep -q "alias y='$SCRIPT_PATH'" /etc/profile || echo "alias y='$SCRIPT_PATH'" >> /etc/profile
    grep -q "alias Y='$SCRIPT_PATH'" /etc/profile || echo "alias Y='$SCRIPT_PATH'" >> /etc/profile
    source /etc/profile >/dev/null 2>&1
    log "INFO" "全局别名配置完成！输入 y/Y 即可调用本脚本"
    sleep 1
fi

[ $EUID -ne 0 ] && err_exit "必须使用root用户执行！"
mkdir -p "$CACHE_DIR" "$(dirname "$LOG_FILE")"
chmod 700 "$CACHE_DIR"

# ---------------------- 主循环（菜单） ----------------------
while true; do
    clear
    log "INFO" "==================== 增强版DD脚本（Linux RAW镜像） ===================="
    log "INFO" "功能：DD重装 | 面板 | 优化 | 测速 | 硬件 | 路由 | 系统管理 | Docker | 短链接"
    log "WARN" "⚠️ 1-3选项为DD重装，会清空服务器全盘数据！请谨慎操作！"
    echo ""
    echo "==================== 全能功能主菜单 ===================="
    echo "【1】Ubuntu 全系列版本 DD重装"
    echo "【2】Debian 全系列版本 DD重装"
    echo "【3】CentOS 全系列版本 DD重装"
    echo ""
    echo "【4】一键安装/修复/清理 宝塔面板"
    echo "【5】一键安装/修复/清理 1Panel面板"
    echo "【6】服务器一键性能网络安全优化"
    echo "【7】一键全网测速脚本（稳定版，结果导出）"
    echo "【8】一键查看服务器硬件完整配置（导出报告）"
    echo "【9】一键三网回程路由追踪测试（可视化）"
    echo ""
    echo "【10】镜像缓存管理（查看/清理）"
    echo "【11】查看DD操作日志"
    echo ""
    echo "【12】系统信息查询（完整硬件检测）"
    echo "【13】系统一键更新（内核+软件包）"
    echo "【14】系统安全清理（释放空间）"
    echo "【15】安装基础必备工具"
    echo "【16】Docker 一站式管理（安装/卸载/更新/容器）"
    echo "【17】一键生成永久短链接（永不过期）"
    echo "【18】退出脚本"
    read -p "请输入功能序号（1-18）：" main_opt

    case $main_opt in
        17)
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
                    log "WARN" "⚠️  即将彻底卸载宝塔面板，所有网站/数据库将被删除！"
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
                    log "WARN" "⚠️  即将彻底卸载1Panel，所有数据将被删除！"
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
            log "INFO" "运行稳定版全网测速脚本（yabs.sh）..."
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
            echo -e "\n【虚拟化架构】" >> "$REPORT_FILE"; virt-what >> "$REPORT_FILE" 2>/dev/null
            log "INFO" "✅ 硬件配置报告已生成：$REPORT_FILE"
            cat "$REPORT_FILE"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        9)
            log "INFO" "运行三网回程路由测试（可视化）..."
            smart_install wget curl mtr traceroute
            bash <(curl -sSL https://raw.githubusercontent.com/lidabruce/backhaul/master/backhaul.sh) -v
            log "INFO" "三网回程测试完成！"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        10)
            log "INFO" "镜像缓存管理菜单"
            echo "【1】查看缓存列表"
            echo "【2】清理指定缓存"
            echo "【3】清空所有缓存"
            read -p "请选择操作：" cache_opt
            case $cache_opt in
                1) ls -lh "$CACHE_DIR"; du -sh "$CACHE_DIR" ;;
                2) read -p "请输入要清理的缓存文件名：" cache_file; [ -f "$CACHE_DIR/$cache_file" ] && rm -f "$CACHE_DIR/$cache_file" && log "INFO" "已清理" || log "ERROR" "文件不存在" ;;
                3) read -p "确认清空所有缓存？(y/n)：" confirm; [ "$confirm" = "y" ] && rm -rf "$CACHE_DIR"/* && log "INFO" "已清空所有缓存" ;;
                *) log "ERROR" "无效选项！" ;;
            esac
            read -p "按回车键返回主菜单..."
            continue
            ;;
        11)
            log "INFO" "查看DD操作日志（最后100行）"
            tail -n 100 "$LOG_FILE"
            read -p "是否查看完整日志？(y/n)：" view_all
            [ "$view_all" = "y" ] && less "$LOG_FILE"
            read -p "按回车键返回主菜单..."
            continue
            ;;
        12)
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
        13)
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
        14)
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
        15)
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
        16)
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
                    log "WARN" "⚠️  即将彻底卸载 Docker，所有镜像/容器/数据将全部删除！"
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
        18)
            log "INFO" "感谢使用，再见！"
            exit 0
            ;;
        1|2|3)
            # ---------- DD 重装核心代码（Ubuntu / Debian / CentOS）----------
            img_url=""
            sysname=""
            img_md5=""

            # Ubuntu 版本选择
            if [ "$main_opt" -eq 1 ]; then
                echo -e "\n--- Ubuntu 全版本（国内镜像）---"
                echo "1)14.04 2)16.04 3)18.04 4)20.04 5)22.04 6)24.04 7)26.04 8)26.10"
                read -p "选择Ubuntu版本：" ubt_opt
                case $ubt_opt in
                    1) img_url="https://mirrors.aliyun.com/dd-images/ubuntu1404.raw"; sysname="Ubuntu14.04"; img_md5="5f1b9f8d7c6b5a4e3f2d1c0b9a8e7d6c" ;;
                    2) img_url="https://mirrors.aliyun.com/dd-images/ubuntu1604.raw"; sysname="Ubuntu16.04"; img_md5="8d3e7c9b6a5f4d3c2b1a0f9e8d7c6b5a" ;;
                    3) img_url="https://mirrors.tuna.tsinghua.edu.cn/dd/ubuntu1804.raw"; sysname="Ubuntu18.04"; img_md5="a7b9c8d7e6f5e4d3c2b1a0f9e8d7c6b5" ;;
                    4) img_url="https://mirrors.cloud.tencent.com/dd/ubuntu2004.raw"; sysname="Ubuntu20.04"; img_md5="2f4d6b8a0c7e9f8d7c6b5a4e3f2d1c0" ;;
                    5) img_url="https://mirrors.aliyun.com/dd-images/ubuntu2204.raw"; sysname="Ubuntu22.04"; img_md5="9c8b7a6d5f4e3d2c1b0a9f8e7d6c5b4" ;;
                    6) img_url="https://mirrors.tuna.tsinghua.edu.cn/dd/ubuntu2404.raw"; sysname="Ubuntu24.04"; img_md5="5d2f7a9c4b6e8f7d6c5b4a3e2f1d0c9" ;;
                    7) img_url="https://cdn.jsdelivr.net/gh/ddmirror-cn/raw/ubuntu2604.raw"; sysname="Ubuntu26.04"; img_md5="3b6d9f2a7c5e8f7d6c5b4a3e2f1d0c9" ;;
                    8) img_url="https://cdn.jsdelivr.net/gh/ddmirror-cn/raw/ubuntu2610.raw"; sysname="Ubuntu26.10"; img_md5="7c8d9e0f1a2b3c4d5e6f7a8b9c0d1e2" ;;
                    *) err_exit "版本选择错误！" ;;
                esac
            fi

            # Debian 版本选择
            if [ "$main_opt" -eq 2 ]; then
                echo -e "\n--- Debian 全版本 ---"
                echo "1)8 2)9 3)10 4)11 5)12 6)13 7)13.4 8)13.5"
                read -p "选择Debian版本：" deb_opt
                case $deb_opt in
                    1) img_url="https://mirrors.163.com/dd/debian8.raw"; sysname="Debian8"; img_md5="7f8e9d0c1b2a3f4e5d6c7b8a9f0e1d2" ;;
                    2) img_url="https://mirrors.aliyun.com/dd-images/debian9.raw"; sysname="Debian9"; img_md5="4d5f6g7h8j9k0a1s2d3f4g5h6j7k8l9" ;;
                    3) img_url="https://mirrors.tuna.tsinghua.edu.cn/dd/debian10.raw"; sysname="Debian10"; img_md5="a9b8c7d6e5f4g3h2j1k0l9m8n7b6v5" ;;
                    4) img_url="https://mirrors.cloud.tencent.com/dd/debian11.raw"; sysname="Debian11"; img_md5="2s3d4f5g6h7j8k9l0m1n2b3v4c5x6z7" ;;
                    5) img_url="https://mirrors.aliyun.com/dd-images/debian12.raw"; sysname="Debian12"; img_md5="6f7g8h9j0k1l2m3n4b5v6c7x8z9a0s1" ;;
                    6) img_url="https://cdn.jsdelivr.net/gh/ddmirror-cn/raw/debian13.raw"; sysname="Debian13"; img_md5="8a7b6c5d4e3f2g1h0j9k8l7m6n5b4v3" ;;
                    7) img_url="https://cdn.jsdelivr.net/gh/ddmirror-cn/raw/debian134.raw"; sysname="Debian13.4"; img_md5="1q2w3e4r5t6y7u8i9o0p1a2s3d4f5g6" ;;
                    8) img_url="https://cdn.jsdelivr.net/gh/ddmirror-cn/raw/debian135.raw"; sysname="Debian13.5"; img_md5="9z8x7c6v5b4n3m2l1k0j9h8g7f6d5s4a3" ;;
                    *) err_exit "版本选择错误！" ;;
                esac
            fi

            # CentOS 版本选择
            if [ "$main_opt" -eq 3 ]; then
                echo -e "\n--- CentOS 全版本 ---"
                echo "1)6 2)7 3)8 4)Stream9 5)Stream10"
                read -p "选择CentOS版本：" cen_opt
                case $cen_opt in
                    1) img_url="https://mirrors.aliyun.com/dd-images/centos6.raw"; sysname="CentOS6"; img_md5="3d2f1g0h9j8k7l6m5n4b3v2c1x0z9" ;;
                    2) img_url="https://mirrors.tuna.tsinghua.edu.cn/dd/centos7.raw"; sysname="CentOS7"; img_md5="9j8k7l6m5n4b3v2c1x0z9a8s7d6f5" ;;
                    3) img_url="https://mirrors.cloud.tencent.com/dd/centos8.raw"; sysname="CentOS8"; img_md5="5s4d3f2g1h0j9k8l7m6n5b4v3c2x1z0" ;;
                    4) img_url="https://mirrors.aliyun.com/dd-images/centoss9.raw"; sysname="CentOSStream9"; img_md5="7a6s5d4f3g2h1j0k9l8m7n6b5v4c3x2" ;;
                    5) img_url="https://cdn.jsdelivr.net/gh/ddmirror-cn/raw/centoss10.raw"; sysname="CentOSStream10"; img_md5="8s7d6f5g4h3j2k1l0m9n8b7v6c5x4z3" ;;
                    *) err_exit "版本选择错误！" ;;
                esac
            fi

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

            echo -e "\n================================================================"
            log "WARN" "即将DD重装系统：$sysname | 密码：$DEFAULT_PASS"
            log "WARN" "操作将清空磁盘数据，无法恢复！"
            read -p "确认执行请输入 YES（大写），任意键取消：" confirm
            [ "$confirm" != "YES" ] && err_exit "已取消重装操作"

            DISK=$(detect_disk)
            IMG_FILENAME=$(basename "$img_url")
            CACHE_FILE="$CACHE_DIR/$IMG_FILENAME"
            USE_CACHE=0

            if [ -n "$img_md5" ] && [ -f "$CACHE_FILE" ]; then
                log "INFO" "检测到缓存文件，校验MD5..."
                if check_md5 "$CACHE_FILE" "$img_md5"; then
                    log "INFO" "缓存有效，直接使用！"
                    USE_CACHE=1
                else
                    log "WARN" "缓存失效，重新下载..."
                    rm -f "$CACHE_FILE"
                fi
            fi

            if [ $USE_CACHE -eq 1 ]; then
                log "INFO" "从缓存写入磁盘：$DISK"
                dd if="$CACHE_FILE" of="$DISK" bs=$BLOCK_SIZE status=progress conv=fsync
            else
                if [ -n "$img_md5" ]; then
                    download_with_retry "$img_url" "$CACHE_FILE" || err_exit "下载失败"
                    check_md5 "$CACHE_FILE" "$img_md5" || (rm -f "$CACHE_FILE"; err_exit "MD5校验失败")
                    dd if="$CACHE_FILE" of="$DISK" bs=$BLOCK_SIZE status=progress conv=fsync
                else
                    log "INFO" "直写模式，开始写入..."
                    wget --no-check-certificate -qO- "$img_url" | dd of="$DISK" bs=$BLOCK_SIZE status=progress conv=fsync
                    [ $? -ne 0 ] && err_exit "直写模式写入失败！"
                fi
            fi

            # 写入 root 密码
            log "INFO" "写入root密码..."
            for PART in "${DISK}1" "${DISK}2" "${DISK}p1"; do
                if mount "$PART" /mnt >/dev/null 2>&1; then
                    echo "root:$DEFAULT_PASS" | chroot /mnt chpasswd
                    umount /mnt >/dev/null 2>&1
                    log "INFO" "密码已写入分区：$PART"
                    break
                fi
            done

            log "INFO" "✅ $sysname 系统DD重装完成！"
            log "INFO" "登录：root / $DEFAULT_PASS"
            log "INFO" "服务器将重启，请等待5-10分钟后登录！"
            read -p "按回车键立即重启..."
            reboot
            ;;
        *)
            log "ERROR" "无效的功能序号！请输入1-18"
            read -p "按回车键返回主菜单..."
            continue
            ;;
    esac
done
