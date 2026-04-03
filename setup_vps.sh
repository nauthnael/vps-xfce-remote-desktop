#!/bin/bash

# Dừng script nếu có lỗi xảy ra
set -e

echo "=== Bắt đầu cài đặt ==="

# Nhận tham số mật khẩu (nếu có)
UBUNTU_PASSWORD=$1

# Bước 0: Kiểm tra và tạo user 'ubuntu'
if id "ubuntu" &>/dev/null; then
    echo "User 'ubuntu' đã tồn tại. Bỏ qua bước tạo user."
else
    echo "User 'ubuntu' chưa tồn tại. Đang tiến hành tạo mới..."
    
    # Nếu không có tham số mật khẩu, yêu cầu người dùng nhập
    if [ -z "$UBUNTU_PASSWORD" ]; then
        read -s -p "Nhập mật khẩu cho user ubuntu: " UBUNTU_PASSWORD
        echo
    fi
    
    # Tạo user 'ubuntu' có thư mục home và shell là bash
    useradd -m -s /bin/bash ubuntu
    
    # Đặt mật khẩu
    echo "ubuntu:$UBUNTU_PASSWORD" | chpasswd
    
    # Thêm user 'ubuntu' vào nhóm sudo
    usermod -aG sudo ubuntu
    echo "Đã tạo thành công user 'ubuntu'."
fi

# Đảm bảo chạy với quyền root (hoặc sudo)
if [ "$EUID" -ne 0 ]; then
  echo "Vui lòng chạy script này với quyền root (ví dụ: sudo bash script.sh)."
  exit 1
fi

# Bước 1: Cập nhật hệ thống
echo "=== Đang chạy apt update ==="
apt update -y
export DEBIAN_FRONTEND=noninteractive
apt upgrade -y

echo "=== Cài đặt các gói tiện ích ==="
apt install -y wget curl gnupg2 software-properties-common apt-transport-https ca-certificates btop

# Bước 3: Tải và cài đặt ARO linux app
echo "=== Cài đặt ARO Linux App ==="
ARO_DOWNLOAD_URL="https://download.aro.network/files/packages/linux/ARO_Desktop_latest_debian.deb" 
wget -O /tmp/aro_app.deb "$ARO_DOWNLOAD_URL"
dpkg -i /tmp/aro_app.deb || apt --fix-broken install -y
# Xoá file rác
rm /tmp/aro_app.deb

# Bước 4: Cài đặt XFCE và Chrome Remote Desktop
echo "=== Cài đặt XFCE ==="
apt install -y xfce4 xfce4-goodies dbus-x11 x11-xserver-utils desktop-base xscreensaver xvfb

echo "=== Cài đặt Chrome Remote Desktop ==="
wget -O /tmp/crd.deb https://dl.google.com/linux/direct/chrome-remote-desktop_current_amd64.deb
dpkg -i /tmp/crd.deb || apt --fix-broken install -y
rm /tmp/crd.deb

# Cấu hình Chrome Remote Desktop sử dụng XFCE cho user ubuntu
echo "Cấu hình XFCE làm môi trường Desktop mặc định cho CRD..."
su - ubuntu -c "bash -c 'echo \"exec /etc/X11/Xsession /usr/bin/xfce4-session\" > ~/.chrome-remote-desktop-session'"
su - ubuntu -c "systemctl --user enable chrome-remote-desktop" || true

echo "=== Cài đặt hoàn tất! ==="
echo ""
echo "Bạn hãy đăng nhập vào Google Chrome Remote Desktop (https://remotedesktop.google.com/headless)"
echo "Chọn hệ điều hành Debian Linux, copy đoạn mã chứng thực (bắt đầu bằng DISPLAY= /opt/google/chrome-remote-desktop/start-host ...)"
echo ""
echo "Chuyển sang user ubuntu bằng lệnh: su - ubuntu"
echo "Sau đó dán đoạn mã vừa copy vào terminal để khởi động CRD."
