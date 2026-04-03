# VPS XFCE & Chrome Remote Desktop Setup

A bash script to fully automate the installation of an XFCE lightweight desktop environment, Google Chrome Remote Desktop, ARO Node, and essential utilities on a fresh Ubuntu 24+ / Debian 12+ VPS.

*(Kéo xuống dưới để đọc hướng dẫn bằng Tiếng Việt)*

## TL;DR (Quick Start)
Run the following command as `root` (or with `sudo`) to download and execute the setup script. 
Replace `<YOUR_PASSWORD>` with the desired password for the newly created `ubuntu` user (if you omit it, the script will ask you interactively).

```bash
wget -O setup_vps.sh https://raw.githubusercontent.com/nauthnael/vps-xfce-remote-desktop/main/setup_vps.sh && chmod +x setup_vps.sh && sudo ./setup_vps.sh <YOUR_PASSWORD>
```


## What does this script do?
1. **User Setup**: Creates an `ubuntu` user (if it doesn't exist) and grants it `sudo` privileges.
2. **System Update & Essential Utilities**: Runs `apt update & upgrade` and installs necessary tools (`wget`, `curl`, `btop`, `gnupg2`, etc.).
3. **ARO Node**: Downloads and installs the latest ARO Desktop Linux App natively.
4. **Desktop Environment**: Installs the XFCE4 desktop environment and related display utilities.
5. **Remote Desktop**: Installs Google Chrome Remote Desktop and configures its session to boot XFCE directly for the `ubuntu` user.

## Post-Installation Guide
1. On your personal computer, go to [Google Chrome Remote Desktop Headless Setup](https://remotedesktop.google.com/headless).
2. Follow the steps, select **Debian Linux** and click "Authorize". Copy the provided authentication command (it starts with `DISPLAY= /opt/google/chrome-remote-desktop/start-host ...`).
3. Back in your VPS terminal, switch to the newly created `ubuntu` user:
   ```bash
   su - ubuntu
   ```
4. Paste the copied authentication command in the terminal and press Enter. You will be prompted to set up a 6-digit PIN.
5. You can now connect to your VPS graphical interface from any device via Chrome Remote Desktop!

<br>
<hr>
<br>

# Cài đặt tự động XFCE & Chrome Remote Desktop cho VPS

Đây là script bash tự động hóa hoàn toàn quá trình cài đặt môi trường desktop nhẹ XFCE, Google Chrome Remote Desktop, ứng dụng ARO, cùng các tiện ích thiết yếu cho một VPS trắng sử dụng Ubuntu 24+ hoặc Debian 12+.

## TL;DR (Cài đặt nhanh)
Chạy lệnh dưới đây bằng quyền `root` để tải và thực thi script. 
Thay thế `<YOUR_PASSWORD>` bằng mật khẩu bạn muốn đặt cho user `ubuntu` (nếu bạn không truyền vào mật khẩu, script sẽ yêu cầu bạn tự nhập sau).

```bash
wget -O setup_vps.sh https://raw.githubusercontent.com/nauthnael/vps-xfce-remote-desktop/main/setup_vps.sh && chmod +x setup_vps.sh && sudo ./setup_vps.sh <YOUR_PASSWORD>
```


## Script này thực hiện những gì?
1. **Khởi tạo User**: Kiểm tra và tạo user `ubuntu` mới, cấp quyền `sudo` đầy đủ.
2. **Cập nhật Hệ thống & Tiện ích**: Chạy `apt update & upgrade` và tự động cài đặt các công cụ cơ bản (`wget`, `curl`, `btop`, `gnupg2`...).
3. **App ARO**: Tải và cài đặt phần mềm ARO Desktop bản mới nhất dành cho Debian.
4. **Môi trường Desktop**: Cài đặt lõi XFCE4 cùng các công cụ hiển thị đồ họa bổ trợ.
5. **Điều khiển từ xa**: Cài đặt Google Chrome Remote Desktop và cấu hình sẵn file `.chrome-remote-desktop-session` để sử dụng XFCE làm giao diện mặc định.

## Hướng dẫn sau cài đặt
1. Mở trình duyệt trên máy tính cá nhân (không phải VPS), truy cập trang [Thiết lập Headless của Chrome Remote Desktop](https://remotedesktop.google.com/headless).
2. Làm theo hướng dẫn, cấp quyền (Authorize), ở bước cuối cùng chọn hệ điều hành **Debian Linux** và copy toàn bộ đoạn mã chứng thực (bắt đầu bằng lệnh `DISPLAY= ...`).
3. Quay lại terminal của VPS, bạn cần chuyển sang user `ubuntu`:
   ```bash
   su - ubuntu
   ```
4. Dán đoạn mã vừa copy vào terminal, ấn Enter. Hệ thống sẽ yêu cầu bạn tạo mã PIN 6 số.
5. Hoàn tất! Từ nay bạn có thể vào [trang web của Remote Desktop](https://remotedesktop.google.com/access) để điều khiển màn hình VPS của mình bất cứ lúc nào.
