#!/usr/bin/env bash

# ==============================================================================
# Linux Server Access & Hardening - Automated Deployment Script
# Author: Jakub Hordynski
# Description: Automatically deploys modular SSH hardening, sudoers rules, 
#              and checks system configuration paths safely.
# ==============================================================================

# Exit immediately if any command fails
set -e

# Ensure script is run with root privileges (sudo)
if [ "$EUID" -ne 0 ]; then
  echo "[-] Error: This script must be run with root privileges (sudo ./setup.sh)."
  exit 1
fi

echo "[+] Starting Linux Server Hardening & Access Deployment..."

# ------------------------------------------------------------------------------
# STEP 1: OpenSSH Server Hardening
# ------------------------------------------------------------------------------
echo "[*] Configuring OpenSSH drop-in hardening..."

# Ensure /etc/ssh/sshd_config.d directory exists
mkdir -p /etc/ssh/sshd_config.d

# Copy hardening configuration file
if [ -f "./configs/ssh/90-hardening.conf" ]; then
  cp ./configs/ssh/90-hardening.conf /etc/ssh/sshd_config.d/90-hardening.conf
  chmod 644 /etc/ssh/sshd_config.d/90-hardening.conf
  echo "[+] OpenSSH hardening configuration copied successfully."
else
  echo "[-] Warning: ./configs/ssh/90-hardening.conf not found. Skipping SSH step."
fi

# Create required groups if they don't exist
for grp in ssh-users PassAuthAny PassAuthInternal PortForwarding GatewayListening X11Users; do
  if ! getent group "$grp" > /dev/null; then
    groupadd "$grp"
    echo "[+] Created group: $grp"
  fi
done

# Validate SSH configuration syntax before restarting service
if sshd -t; then
  systemctl restart ssh
  echo "[+] OpenSSH service restarted successfully with new configuration."
else
  echo "[-] CRITICAL: SSH configuration syntax error detected! Service not restarted."
  exit 1
fi

# ------------------------------------------------------------------------------
# STEP 2: Sudoers Privilege Delegation
# ------------------------------------------------------------------------------
echo "[*] Configuring granular sudo policies..."

if [ -f "./configs/sudoers/90-operator-rules" ]; then
  cp ./configs/sudoers/90-operator-rules /etc/sudoers.d/90-operator-rules
  # Enforce strict 0440 permissions required by sudo
  chmod 440 /etc/sudoers.d/90-operator-rules
  
  # Validate sudoers syntax
  if visudo -cf /etc/sudoers.d/90-operator-rules; then
    echo "[+] Sudoers rules deployed and validated successfully."
  else
    echo "[-] CRITICAL: Sudoers syntax validation failed! Removing faulty file."
    rm -f /etc/sudoers.d/90-operator-rules
    exit 1
  fi
else
  echo "[-] Warning: ./configs/sudoers/90-operator-rules not found. Skipping sudoers step."
fi

# ------------------------------------------------------------------------------
# STEP 3: GRUB Serial Console Redirection Notice
# ------------------------------------------------------------------------------
if [ -f "./configs/grub/grub-serial.conf" ]; then
  echo "[*] Checking GRUB serial console configuration..."
  echo "[!] NOTE: Automatic GRUB modification requires caution."
  echo "    Please verify /etc/default/grub manually or apply the snippet from configs/grub/grub-serial.conf"
  echo "    and run 'sudo update-grub' if you are deploying on a fresh headless server."
fi

echo "=============================================================================="
echo "[+] Deployment completed successfully! Your Linux server access is now hardened."
echo "=============================================================================="
