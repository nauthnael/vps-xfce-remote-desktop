# VPS Setup: XFCE + Chrome Remote Desktop + ARO

Automated script to deploy a secure XFCE desktop environment and Google Chrome Remote Desktop on Ubuntu/Debian VPS instances.

## Features
- **Secure SSH**: Disables password authentication and root login (if pubkey is set).
- **Desktop Environment**: Installs XFCE4 and Chrome Remote Desktop.
- **Security**: Configures UFW firewall, Fail2ban, and Unattended Upgrades.
- **Optimization**: Configures Swap and optimizes XFCE (disables screensaver and power management popups).
- **ARO App**: Option to install the ARO Linux App automatically.

## Usage
Run the script as root:
```bash
sudo bash setup_vps.sh "YOUR_SSH_PUBLIC_KEY" [aro]
```
- Replace `"YOUR_SSH_PUBLIC_KEY"` with your actual public key.
- Add `aro` as the second argument to skip the ARO installation prompt and install it automatically.

## Post-Installation
After the script completes, follow the instructions to link your instance to Chrome Remote Desktop.
