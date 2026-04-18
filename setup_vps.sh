#!/bin/bash

# Dừng script nếu có lỗi xảy ra
set -e

# Tự động dọn dẹp file cài đặt tạm trong /tmp khi thoát script
trap 'rm -f /tmp/*.deb /tmp/google-chrome-key.gpg' EXIT

# Rollback SSH config nếu script gặp lỗi sau bước SSH Hardening
SSH_HARDENING_DONE=false
trap 'on_error' ERR

on_error() {
    local exit_code=$?
    echo ""
    echo "⚠️ Script gặp lỗi (exit code: $exit_code)!"
    
    # Chỉ rollback nếu đã chạy qua SSH Hardening
    if [ "$SSH_HARDENING_DONE" = "true" ] && [ -f /etc/ssh/sshd_config.d/99-hardening.conf ]; then
        echo "Đang rollback SSH config để tránh lock out..."
        sed -i 's/^PermitRootLogin.*/PermitRootLogin yes/' /etc/ssh/sshd_config.d/99-hardening.conf 2>/dev/null
        systemctl restart ssh 2>/dev/null && echo "✅ Đã rollback: Root login vẫn khả dụng." || true
    fi
    
    exit $exit_code
}

echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Bắt đầu cài đặt ==="

# 🔴 Kiểm tra quyền root (Chuyển lên đầu tiên)
if [ "$EUID" -ne 0 ]; then
  echo "⚠️ Vui lòng chạy script này với quyền root (ví dụ: sudo bash setup_vps.sh)."
  exit 1
fi

# 🟡 Kiểm tra kiến trúc CPU phải là amd64
ARCH=$(dpkg --print-architecture)
if [ "$ARCH" != "amd64" ]; then
    echo "⚠️ Script này chỉ hỗ trợ kiến trúc amd64. Kiến trúc hiện tại của máy: $ARCH"
    exit 1
fi

# Nhận tham số cấu hình tĩnh
UBUNTU_SSH_KEY=$1
AUTO_INSTALL_ARO=${2,,} # Chuyển param thứ 2 thành chữ thường (ví dụ: aro)

# Bước 1: Kiểm tra và tạo user 'ubuntu'
if id "ubuntu" &>/dev/null; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] User 'ubuntu' đã tồn tại. Bỏ qua bước tạo user."
    
    # Append SSH key nếu được truyền vào và chưa có trong authorized_keys
    if [ -n "$UBUNTU_SSH_KEY" ]; then
        mkdir -p /home/ubuntu/.ssh
        grep -qxF "$UBUNTU_SSH_KEY" /home/ubuntu/.ssh/authorized_keys 2>/dev/null || \
            echo "$UBUNTU_SSH_KEY" >> /home/ubuntu/.ssh/authorized_keys
        chown -R ubuntu:ubuntu /home/ubuntu/.ssh
        chmod 700 /home/ubuntu/.ssh
        chmod 600 /home/ubuntu/.ssh/authorized_keys
        echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Đã cập nhật SSH key cho user 'ubuntu'."
    fi
    # Lock password
    passwd -l ubuntu
    
    # Đảm bảo NOPASSWD được cấu hình dù user đã tồn tại trước
    if [ ! -f /etc/sudoers.d/ubuntu-nopasswd ]; then
        echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu-nopasswd
        chmod 440 /etc/sudoers.d/ubuntu-nopasswd
        echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Đã cấu hình sudo NOPASSWD cho user ubuntu."
    fi
else
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] User 'ubuntu' chưa tồn tại. Đang tiến hành tạo mới..."
    
    # Nếu không có tham số khóa, yêu cầu người dùng nhập
    # Dùng || true để tránh crash trap/set -e nếu người dùng ấn Ctrl+D
    if [ -z "$UBUNTU_SSH_KEY" ]; then
        read -p "Nhập SSH public key cho user ubuntu: " UBUNTU_SSH_KEY || true
    fi
    
    useradd -m -s /bin/bash ubuntu
    usermod -aG sudo ubuntu

    # Cấu hình sudo NOPASSWD cho ubuntu
    # Cần thiết vì user ubuntu không có password (đã bị lock)
    # SSH key đã đảm bảo bảo mật ở tầng login nên NOPASSWD là hợp lý
    echo "ubuntu ALL=(ALL) NOPASSWD:ALL" > /etc/sudoers.d/ubuntu-nopasswd
    chmod 440 /etc/sudoers.d/ubuntu-nopasswd

    # Cài SSH key nếu có
    if [ -n "$UBUNTU_SSH_KEY" ]; then
        mkdir -p /home/ubuntu/.ssh
        echo "$UBUNTU_SSH_KEY" > /home/ubuntu/.ssh/authorized_keys
        chown -R ubuntu:ubuntu /home/ubuntu/.ssh
        chmod 700 /home/ubuntu/.ssh
        chmod 600 /home/ubuntu/.ssh/authorized_keys
    fi

    # Lock password, chỉ cho phép login bằng SSH key
    passwd -l ubuntu
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Đã tạo thành công user 'ubuntu'."
fi

# Bước 2: Cập nhật hệ thống
export DEBIAN_FRONTEND=noninteractive
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Đang chạy apt update ==="
apt update -y
apt upgrade -y


# Bước 3: Kiểm tra và tạo Swap
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Kiểm tra Swap ==="

# Kiểm tra swap đã tồn tại chưa
SWAP_TOTAL=$(free -m | awk '/^Swap:/ {print $2}')
SWAP_TOTAL=${SWAP_TOTAL:-0}  # Guard: nếu rỗng thì mặc định là 0, tránh crash set -e

if [ "$SWAP_TOTAL" -gt 0 ]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Swap đã tồn tại: ${SWAP_TOTAL}MB. Bỏ qua bước tạo swap."
else
    # Tính dung lượng disk (GB) của phân vùng root
    DISK_TOTAL_GB=$(df -BG / | awk 'NR==2 {gsub("G",""); print $2}')
    DISK_TOTAL_GB=${DISK_TOTAL_GB:-20}  # Guard: mặc định 20GB nếu không đọc được (overlay/tmpfs)

    # Xác định kích thước swap theo dung lượng disk
    if [ "$DISK_TOTAL_GB" -lt 16 ]; then
        SWAP_SIZE="1G"
        SWAP_MB=1024
    elif [ "$DISK_TOTAL_GB" -lt 30 ]; then
        SWAP_SIZE="2G"
        SWAP_MB=2048
    else
        # Trên 30GB (bao gồm trên 50GB)
        SWAP_SIZE="4G"
        SWAP_MB=4096
    fi

    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Disk: ${DISK_TOTAL_GB}GB — Sẽ tạo swap ${SWAP_SIZE}..."

    # Tạo swap file
    fallocate -l "$SWAP_SIZE" /swapfile || dd if=/dev/zero of=/swapfile bs=1M count="$SWAP_MB" status=progress

    # Phân quyền bảo mật cho swapfile
    chmod 600 /swapfile

    # Kích hoạt swap
    mkswap /swapfile
    swapon /swapfile

    # Mount tự động khi reboot
    if ! grep -q '/swapfile' /etc/fstab; then
        echo '/swapfile none swap sw 0 0' >> /etc/fstab
    fi

    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Đã tạo và kích hoạt swap ${SWAP_SIZE}."
fi

# Tối ưu swap cho VPS (áp dụng dù swap mới hay đã có sẵn)
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Áp dụng cấu hình tối ưu swap..."

# swappiness=10: Ưu tiên dùng RAM, chỉ dùng swap khi RAM còn 10%
# Mặc định Ubuntu là 60 — quá cao cho VPS
# vfs_cache_pressure=50: Giữ cache file system lâu hơn trong RAM
# Mặc định là 100 — giảm xuống 50 giúp VPS phản hồi nhanh hơn
cat > /etc/sysctl.d/99-swap-optimize.conf << EOF
vm.swappiness=10
vm.vfs_cache_pressure=50
EOF

# Áp dụng ngay không cần reboot
sysctl -p /etc/sysctl.d/99-swap-optimize.conf

echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Cấu hình swap tối ưu đã được áp dụng."
echo "   vm.swappiness=10 (mặc định Ubuntu: 60)"
echo "   vm.vfs_cache_pressure=50 (mặc định Ubuntu: 100)"


# Bước 4: SSH Hardening
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === SSH Hardening ==="

# Kiểm tra SSH key của ubuntu hợp lệ trước khi disable root login
# Tránh lock out hoàn toàn nếu key ubuntu chưa được setup
UBUNTU_AUTH_KEYS="/home/ubuntu/.ssh/authorized_keys"
if [ ! -s "$UBUNTU_AUTH_KEYS" ]; then
    echo "⚠️  CẢNH BÁO: /home/ubuntu/.ssh/authorized_keys trống hoặc chưa tồn tại."
    echo "    PermitRootLogin sẽ KHÔNG bị disable để tránh lock out."
    PERMIT_ROOT_LOGIN="yes"
else
    echo "✅ SSH key của ubuntu đã sẵn sàng. Sẽ disable root login."
    PERMIT_ROOT_LOGIN="no"
fi

# Ghi override vào file riêng để không bị reset khi update sshd
cat > /etc/ssh/sshd_config.d/99-hardening.conf << EOF
PasswordAuthentication no
PermitRootLogin ${PERMIT_ROOT_LOGIN}
PubkeyAuthentication yes
AuthorizedKeysFile .ssh/authorized_keys
X11Forwarding no
AllowTcpForwarding no
EOF

# Kiểm tra config hợp lệ trước khi restart
# Dùng if/else thay vì && || để tránh logic sai khi systemctl fail
if sshd -t 2>/dev/null; then
    systemctl restart ssh
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ SSH hardening hoàn tất. PermitRootLogin=${PERMIT_ROOT_LOGIN}"
    SSH_HARDENING_DONE=true
else
    echo "⚠️ SSH config có lỗi, KHÔNG restart để tránh mất kết nối."
    echo "Kiểm tra lại: /etc/ssh/sshd_config.d/99-hardening.conf"
fi


# Bước 5: Cài đặt các gói tiện ích và cấu hình bảo vệ chủ động
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Cài đặt các gói tiện ích ==="
apt install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates btop fail2ban unattended-upgrades

# Cấu hình fail2ban cho SSH
cat > /etc/fail2ban/jail.d/ssh.conf << EOF
[sshd]
enabled = true
maxretry = 5
bantime = 1h
findtime = 10m
EOF

systemctl enable fail2ban
systemctl start fail2ban
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Fail2ban đã được cài và kích hoạt."

# Chỉ enable security updates tự động, không upgrade package thường
cat > /etc/apt/apt.conf.d/20auto-upgrades << EOF
APT::Periodic::Update-Package-Lists "1";
APT::Periodic::Unattended-Upgrade "1";
APT::Periodic::AutocleanInterval "7";
EOF

cat > /etc/apt/apt.conf.d/50unattended-upgrades << EOF
Unattended-Upgrade::Allowed-Origins {
    "\${distro_id}:\${distro_codename}-security";
};
Unattended-Upgrade::AutoFixInterruptedDpkg "true";
Unattended-Upgrade::MinimalSteps "true";
Unattended-Upgrade::Remove-Unused-Dependencies "true";
EOF

echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Unattended security updates đã được kích hoạt."


# Bước 6: Cấu hình UFW Firewall
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Cấu hình UFW Firewall ==="

apt install -y ufw

ufw default deny incoming
ufw default allow outgoing
ufw allow ssh
ufw allow 11235/tcp  # OptimAI crawl4ai node

# KHÔNG disable iptables của Docker vì Docker cần tự quản lý
# iptables để port mapping hoạt động đúng

ufw --force enable
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] UFW Firewall đã được kích hoạt."


# Bước 7: Cài đặt XFCE và các thư viện cần thiết cho CRD
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Cài đặt XFCE và các thư viện cần thiết cho CRD ==="
apt install -y xfce4 xfce4-goodies dbus-x11 x11-xserver-utils desktop-base xvfb \
    xserver-xorg-core xserver-xorg-video-dummy xbase-clients python3-psutil python3-xdg psmisc \
    xscreensaver xauth libgl1-mesa-dri

# Xoá light-locker để tránh lỗi đen màn hình / xung đột lightdm trên môi trường headless
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Xoá light-locker để ngăn xung đột với LightDM..."
apt purge -y light-locker 2>/dev/null || true

# Cấu hình Xwrapper để cho phép user non-console chạy Xorg
# Cần thiết cho CRD trên VPS headless - thiếu file này Xorg sẽ bị từ chối
cat > /etc/X11/Xwrapper.config << EOF
allowed_users=anybody
needs_root_rights=yes
EOF
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Đã cấu hình Xwrapper cho môi trường headless."


# Kiểm tra kết nối internet trước khi download
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Kiểm tra kết nối internet..."
if ! ping -c 1 -W 3 8.8.8.8 &>/dev/null && ! ping -c 1 -W 3 1.1.1.1 &>/dev/null; then
    echo "⚠️ CẢNH BÁO: Không có kết nối internet. Script sẽ tiếp tục nhưng có thể fail ở bước download."
    read -p "Bạn có muốn tiếp tục? (y/n): " -r CONTINUE_CHOICE || true
    if [[ ! "$CONTINUE_CHOICE" =~ ^[Yy]$ ]]; then
        echo "Script dừng theo yêu cầu của người dùng."
        exit 0
    fi
else
    echo "✅ Kết nối internet hoạt động bình thường."
fi

# Bước 8: Cài đặt Chrome Remote Desktop
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Cài đặt Chrome Remote Desktop ==="

# Phép màu trên Ubuntu 22.04: Vá biểu thức chính quy (NAME_REGEX) để adduser chấp nhận dấu gạch dưới "_"
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Cấu hình adduser.conf và tạo trước user _crd_network..."
if grep -q "^NAME_REGEX=" /etc/adduser.conf 2>/dev/null; then
    sed -i 's/^NAME_REGEX=.*/NAME_REGEX="^[a-z_][-a-z0-9_]*\$"/' /etc/adduser.conf
else
    echo 'NAME_REGEX="^[a-z_][-a-z0-9_]*$"' >> /etc/adduser.conf
fi

if grep -q "^NAME_REGEX_SYSTEM=" /etc/adduser.conf 2>/dev/null; then
    sed -i 's/^NAME_REGEX_SYSTEM=.*/NAME_REGEX_SYSTEM="^[a-z_][-a-z0-9_]*\$"/' /etc/adduser.conf
else
    echo 'NAME_REGEX_SYSTEM="^[a-z_][-a-z0-9_]*$"' >> /etc/adduser.conf
fi

# Pre-tạo system user thủ công (với force-badname) trước khi post-install script của CRD gọi tới lệnh adduser
adduser --system --quiet --group --force-badname _crd_network || true

# Thử cài CRD từ file .deb trước (nhanh hơn)
CRD_DEB_URL="https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb"
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Thử tải CRD từ file .deb..."

if wget -q --spider "$CRD_DEB_URL" 2>/dev/null && wget -O /tmp/crd.deb "$CRD_DEB_URL" 2>/dev/null; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Tải .deb thành công, đang cài đặt..."
    if apt install -y /tmp/crd.deb 2>/dev/null; then
        echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ CRD đã được cài từ file .deb"
        CRD_INSTALL_SUCCESS=true
    else
        echo "⚠️ Cài .deb thất bại, sẽ thử cài từ repo..."
        CRD_INSTALL_SUCCESS=false
    fi
else
    echo "⚠️ Không thể tải file .deb (404 hoặc lỗi mạng), sẽ thử cài từ repo..."
    CRD_INSTALL_SUCCESS=false
fi

# Fallback: Cài từ Google Chrome repository nếu .deb fail
if [ "$CRD_INSTALL_SUCCESS" != "true" ]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Cài CRD từ Google Chrome repository..."
    
    # Thêm Google Chrome repo chính thức
    wget -q -O /tmp/google-chrome-key.gpg https://dl.google.com/linux/linux_signing_key.pub
    gpg --dearmor -o /usr/share/keyrings/google-chrome-archive-keyring.gpg /tmp/google-chrome-key.gpg
    rm -f /tmp/google-chrome-key.gpg
    
    echo "deb [arch=amd64 signed-by=/usr/share/keyrings/google-chrome-archive-keyring.gpg] http://dl.google.com/linux/chrome/deb/ stable main" > /etc/apt/sources.list.d/google-chrome.list
    
    # Update apt cache để nhận repo mới
    apt update -y
    
    # Cài Chrome Remote Desktop từ repo
    apt install -y chrome-remote-desktop
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ CRD đã được cài từ Google repository"
fi

# Cấu hình Chrome Remote Desktop sử dụng XFCE cho user ubuntu
# Sử dụng phương pháp chown direct thay vì `su -` để tránh lỗi session PAM trên VPS rút gọn
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Cấu hình XFCE làm môi trường Desktop mặc định cho CRD..."
HOME_UBUNTU=$(getent passwd ubuntu | cut -d: -f6)
echo "exec startxfce4" > "$HOME_UBUNTU/.chrome-remote-desktop-session"
chown ubuntu:ubuntu "$HOME_UBUNTU/.chrome-remote-desktop-session"

# Fix permission thư mục .config/chrome-remote-desktop
# Script chạy bằng root nên dễ tạo thư mục với owner root
# CRD sẽ bị lỗi FILE_ERROR_ACCESS_DENIED nếu thư mục không thuộc ubuntu
mkdir -p "$HOME_UBUNTU/.config/chrome-remote-desktop"
chown -R ubuntu:ubuntu "$HOME_UBUNTU/.config"
chmod 700 "$HOME_UBUNTU/.config/chrome-remote-desktop"

# Fix popup "Authentication is required to create a color managed device"
# colord daemon yêu cầu password mỗi khi XFCE khởi động trên VPS headless
# Tạo polkit rule để tự động cho phép user ubuntu không cần nhập password
mkdir -p /etc/polkit-1/localauthority/50-local.d/
cat > /etc/polkit-1/localauthority/50-local.d/45-allow-colord.pkla << EOF
[Allow colord for ubuntu]
Identity=unix-user:ubuntu
Action=org.freedesktop.color-manager.create-device;org.freedesktop.color-manager.create-profile;org.freedesktop.color-manager.delete-device;org.freedesktop.color-manager.delete-profile;org.freedesktop.color-manager.modify-device;org.freedesktop.color-manager.modify-profile
ResultAny=yes
ResultInactive=yes
ResultActive=yes
EOF
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Đã tắt popup xác thực colord cho user ubuntu."

# Disable xscreensaver autostart để tiết kiệm CPU/RAM trên VPS headless
# Giữ package xscreensaver đã cài (CRD cần), chỉ ngăn XFCE tự khởi động daemon
mkdir -p "$HOME_UBUNTU/.config/autostart"
cat > "$HOME_UBUNTU/.config/autostart/xscreensaver.desktop" << EOF
[Desktop Entry]
Hidden=true
EOF
chown -R ubuntu:ubuntu "$HOME_UBUNTU/.config/autostart"

# Cấu hình XFCE Power Manager: tắt toàn bộ display sleep/blank/switch off
# Bật Presentation Mode để VPS chạy hết hiệu năng, không bị screensaver ngốn CPU
mkdir -p "$HOME_UBUNTU/.config/xfce4/xfconf/xfce-perchannel-xml"

cat > "$HOME_UBUNTU/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-power-manager.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-power-manager" version="1.0">
  <property name="xfce4-power-manager" type="empty">
    <property name="blank-on-ac" type="int" value="0"/>
    <property name="dpms-enabled" type="bool" value="false"/>
    <property name="dpms-on-ac-sleep" type="uint" value="0"/>
    <property name="dpms-on-ac-off" type="uint" value="0"/>
    <property name="presentation-mode" type="bool" value="true"/>
    <property name="lid-action-on-ac" type="uint" value="0"/>
  </property>
</channel>
EOF

# Cấu hình xfce4-screensaver: tắt hoàn toàn
cat > "$HOME_UBUNTU/.config/xfce4/xfconf/xfce-perchannel-xml/xfce4-screensaver.xml" << EOF
<?xml version="1.0" encoding="UTF-8"?>
<channel name="xfce4-screensaver" version="1.0">
  <property name="saver" type="empty">
    <property name="enabled" type="bool" value="false"/>
    <property name="mode" type="int" value="0"/>
  </property>
  <property name="lock" type="empty">
    <property name="enabled" type="bool" value="false"/>
    <property name="saver-activation-enabled" type="bool" value="false"/>
  </property>
</channel>
EOF

chown -R ubuntu:ubuntu "$HOME_UBUNTU/.config/xfce4"
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] ✅ Đã cấu hình Power Manager và tắt screensaver cho XFCE."


# Bước 9: Cài đặt ARO linux app (Có lựa chọn)
if [ "$AUTO_INSTALL_ARO" == "aro" ]; then
    INSTALL_ARO_CHOICE="y"
else
    echo ""
    read -p "Bạn có muốn cài đặt ARO Linux App không? (y/n): " -r INSTALL_ARO_CHOICE || true
fi

if [[ "$INSTALL_ARO_CHOICE" =~ ^[Yy]$ ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Cài đặt ARO Linux App ==="
    ARO_DOWNLOAD_URL="https://download.aro.network/files/packages/linux/ARO_Desktop_latest_debian.deb" 
    
    # Verify link download bằng wget spider
    if wget -q --spider "$ARO_DOWNLOAD_URL" 2>/dev/null; then
        wget -O /tmp/aro_app.deb "$ARO_DOWNLOAD_URL"
        apt install -y /tmp/aro_app.deb
    else
        echo "⚠️ Không thể tải ARO từ URL cung cấp. Bỏ qua cài đặt."
    fi
else
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Bỏ qua cài đặt ARO Linux App."
fi


# Bước 10: Dọn dẹp hệ thống
echo ""
read -p "Bạn có muốn dọn dẹp các gói (packages) thừa không (Gợi ý: nên dọn dẹp)? (y/n): " -r CLEANUP_CHOICE || true
if [[ "$CLEANUP_CHOICE" =~ ^[Yy]$ ]]; then
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Đang dọn dẹp hệ thống ==="
    apt autoremove -y
    apt clean
else
    echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] Bỏ qua dọn dẹp."
fi


echo ""
echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Kiểm tra bảo mật ==="

# Kiểm tra SSH password auth đã tắt chưa
SSH_PASS=$(sshd -T 2>/dev/null | grep "^passwordauthentication" | awk '{print $2}')
if [ "$SSH_PASS" = "no" ]; then
    echo "✅ SSH: Password authentication đã tắt"
else
    echo "⚠️  SSH: Password authentication vẫn còn BẬT - kiểm tra lại sshd_config"
fi

# Kiểm tra UFW
UFW_STATUS=$(ufw status | head -1)
echo "✅ Firewall: $UFW_STATUS"

# Kiểm tra Fail2ban
if systemctl is-active --quiet fail2ban; then
    echo "✅ Fail2ban: Đang chạy"
else
    echo "⚠️  Fail2ban: Không chạy"
fi

# Kiểm tra user ubuntu không có password
UBUNTU_PASS_STATUS=$(passwd -S ubuntu 2>/dev/null | awk '{print $2}')
if [ "$UBUNTU_PASS_STATUS" = "L" ]; then
    echo "✅ User ubuntu: Password đã bị lock, chỉ dùng SSH key"
else
    echo "⚠️  User ubuntu: Password chưa bị lock"
fi

# Kiểm tra sudo NOPASSWD
if [ -f /etc/sudoers.d/ubuntu-nopasswd ]; then
    echo "✅ Sudo: NOPASSWD đã được cấu hình cho user ubuntu"
else
    echo "⚠️  Sudo: NOPASSWD chưa được cấu hình - user ubuntu có thể không dùng được sudo"
fi

# Kiểm tra Xwrapper.config
if [ -f /etc/X11/Xwrapper.config ]; then
    echo "✅ Xwrapper: Đã được cấu hình cho môi trường headless"
else
    echo "⚠️  Xwrapper: Chưa được cấu hình - CRD có thể không khởi động Xorg"
fi

# Liệt kê port đang listen
echo ""
echo "=== Các port đang mở ==="
ss -tlnp | grep LISTEN


echo "[$(date +'%Y-%m-%dT%H:%M:%S%z')] === Cài đặt hoàn tất! ==="
echo ""
echo "=== 📋 Tóm tắt cấu hình ==="
echo "Swap: ${SWAP_SIZE:-Đã có sẵn ${SWAP_TOTAL}MB}"
echo "SSH: Password auth OFF, Root login ${PERMIT_ROOT_LOGIN^^}"
echo "Firewall: UFW enabled (ports 22, 11235 allowed)"
echo "Desktop: XFCE + CRD, Power saving disabled"
if [[ "$INSTALL_ARO_CHOICE" =~ ^[Yy]$ ]]; then
    echo "ARO: Installed"
else
    echo "ARO: Skipped"
fi
echo ""
echo "=== Hướng dẫn kích hoạt Chrome Remote Desktop ==="
echo ""
echo "1. Vào: https://remotedesktop.google.com/headless"
echo "2. Chọn Debian Linux → Begin → Authorize"
echo "3. Copy phần --code='...' từ lệnh được cấp"
echo "4. Chạy lệnh sau trên VPS (không cần password ubuntu):"
echo ""
echo "   sudo -u ubuntu /opt/google/chrome-remote-desktop/start-host \\"
echo "       --code='AUTH_CODE_TỪ_GOOGLE' \\"
echo "       --redirect-url='https://remotedesktop.google.com/_/oauthredirect' \\"
echo "       --name='\$(hostname)'"
