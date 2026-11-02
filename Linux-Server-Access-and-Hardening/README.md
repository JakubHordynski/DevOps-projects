# Linux Server Access & Security Hardening Blueprint

A comprehensive, modular configuration template and step-by-step engineering guide for securing remote access, delegating privileges, and establishing out-of-band recovery channels on Debian, Ubuntu, and Kali Linux servers.

Instead of directly modifying monolithic system configuration files like `/etc/ssh/sshd_config` or `/etc/sudoers`—which often leads to merge conflicts during package upgrades or accidental system lockouts—this project implements **modular drop-in configurations** (`sshd_config.d`, `sudoers.d`) alongside kernel-level serial console redirection (`GRUB2`) and web-based system telemetry (`Cockpit`).

---

## Architecture & Access Channels Overview

This blueprint configures five distinct administrative and recovery access layers for a Linux server or Virtual Machine:

| Access Layer | Protocol / Mechanism | Default Port | Target Port (Hardened) | Purpose |
| :--- | :--- | :--- | :--- | :--- |
| **Primary CLI Admin** | OpenSSH (Ed25519 Keys + Match Rules) | `22/TCP` | `6969/TCP` (VM) / `2220` (NAT) | Daily secure shell administration and tunneling |
| **Privilege Escalation** | Sudo (`sudoers.d` drop-in policies) | Local CLI | N/A | Least-privilege command execution without root sharing |
| **Emergency Out-of-Band** | RS-232 Serial Console (`ttyS0` / Named Pipe)| `COM1` (`57600` baud) | `\\.\pipe\myvbox` | Direct kernel/bootloader access when networking or SSH fails|
| **Web Administration** | Cockpit Web Service (HTTPS) | `9090/TCP` | `9090/TCP`| Real-time resource monitoring, logs, and web terminal|
| **Hypervisor GUI Fallback**| VirtualBox VRDP (Remote Desktop) | `3389/TCP` | `3389/TCP` | Full graphical desktop session at the hypervisor layer |

---

## Repository Structure

All ready-to-use configuration files are located inside the `configs/` directory so you can directly copy them onto your target Linux machine:

    Linux-Server-Access-and-Hardening/
    ├── configs/
    │   ├── grub/
    │   │   └── grub-serial.conf        # Kernel parameters for ttyS0 serial console access
    │   ├── ssh/
    │   │   └── 90-hardening.conf       # Modular OpenSSH hardening, cipher filtering & Match rules
    │   └── sudoers/
    │       └── 90-operator-rules       # Least-privilege sudo command delegation template
    └── README.md                       # Complete implementation and troubleshooting guide

---

## Prerequisites

- **Target System:** Any Debian-based Linux distribution (Ubuntu Server, Debian, Kali Linux) running on bare metal, cloud VPS, or a local hypervisor.
- **Hypervisor (if testing locally):** Oracle VM VirtualBox + **VirtualBox Extension Pack** (required for VRDP remote display support).
- **Client Tools (Host OS):**
  - OpenSSH Client (`ssh`, `ssh-keygen` — built into Windows 11, Linux, and macOS)
  - **PuTTY** (for connecting to local Windows Named Pipes over serial console)
  - **Remote Desktop Connection (`mstsc.exe`)** or any RDP client

---

## Step-by-Step Implementation Guide

Follow these 6 stages in order to deploy the configurations onto your own Linux server or virtual machine.

### Stage 1: Asymmetric SSH Key Authentication & NAT Networking

Using password-based SSH authentication exposes servers to brute-force attacks. In this stage, we configure asymmetric **Ed25519** cryptography.

#### 1.1 Install OpenSSH and Create an Administrative User (On Linux VM)
Update package repositories, install the OpenSSH daemon, and create a dedicated administrative user (`sysadmin`) with `sudo` privileges:

    sudo apt update && sudo apt install -y openssh-server
    sudo adduser sysadmin
    sudo usermod -aG sudo sysadmin

#### 1.2 Configure VirtualBox NAT Port Forwarding (If using a VM behind NAT)
If your VM uses a **NAT** network adapter instead of a Bridged Adapter (useful when DHCP on external networks blocks virtual MAC addresses), configure port forwarding in **VirtualBox -> VM Settings -> Network -> Adapter 1 (NAT) -> Advanced -> Port Forwarding**:
- **Name:** `SSH-Initial`
- **Protocol:** `TCP`
- **Host IP:** `127.0.0.1` (or leave blank)
- **Host Port:** `2222`
- **Guest Port:** `22`

#### 1.3 Generate Ed25519 Keys (On Host Machine)
Open a terminal (CMD/PowerShell on Windows 11, or Bash on Linux/macOS) and generate an Ed25519 key pair:

    ssh-keygen -t ed25519

This generates two files in your `~/.ssh/` directory:
- `id_ed25519` — Your **private key** (never share or move this to the server).
- `id_ed25519.pub` — Your **public key** (to be placed on the Linux server).

#### 1.4 Authorize the Public Key and Lock Permissions (On Linux VM)
Log into the Linux machine as `sysadmin`, create the `.ssh` directory, and paste the contents of your host's `id_ed25519.pub` into `~/.ssh/authorized_keys`:

    mkdir -p /home/sysadmin/.ssh
    nano /home/sysadmin/.ssh/authorized_keys

**Critical Security Requirement:** OpenSSH enforces strict ownership checks. If other users have write permissions to `~/.ssh` or `authorized_keys`, the SSH daemon will refuse key authentication. Apply the following permissions:

    chmod 700 /home/sysadmin/.ssh
    chmod 600 /home/sysadmin/.ssh/authorized_keys
    chown -R sysadmin:sysadmin /home/sysadmin/.ssh

Ensure `PubkeyAuthentication yes` is enabled in `/etc/ssh/sshd_config`, restart SSH (`sudo systemctl restart ssh`), and test logging in from your host machine:

    ssh -p 2222 sysadmin@127.0.0.1

---

### Stage 2: Modular OpenSSH Server Hardening (`sshd_config.d`)

Modern OpenSSH servers include the directive `Include /etc/ssh/sshd_config.d/*.conf` inside the main configuration file. Files inside this directory are loaded in **lexicographical (alphabetical/numerical) order**. By naming our file `90-hardening.conf`, we ensure it loads at the end and cleanly overrides default settings without modifying system-managed files.

#### 2.1 How the Hardening Configuration Works (`configs/ssh/90-hardening.conf`)
- **Custom Port (`Port 6969`):** Moves SSH off the default port `22`.
- **Network & Group Filtering (`AllowGroups`, `AllowUsers`, `DenyUsers`):** Restricts SSH login exclusively to members of `ssh-users` or `sudo`, permits connections from the local NAT gateway (`10.0.2.2`) and private subnet (`192.168.0.0/16`), and explicitly blocks `172.16.0.0/12`.
- **Cipher Blacklisting (`Ciphers -3des-cbc,...`):** Uses the `-` prefix to strip legacy CBC and CTR symmetric ciphers from the SSH handshake while retaining modern AEAD ciphers (such as `chacha20-poly1305` and `aes256-gcm`).
- **Zero-Trust Global Defaults:** Disables password authentication, TCP port forwarding, gateway ports, and X11 forwarding globally.
- **Granular `Match Group` Blocks:** Selectively re-enables specific capabilities (such as password login from `10.0.0.0/8`, local port forwarding, remote `GatewayPorts`, or `X11Forwarding`) based on Linux group membership.

#### 2.2 Deploy the Configuration
1. Copy `configs/ssh/90-hardening.conf` from this repository to `/etc/ssh/sshd_config.d/90-hardening.conf` on your server:

       sudo cp configs/ssh/90-hardening.conf /etc/ssh/sshd_config.d/90-hardening.conf

2. Create the dedicated Linux security groups referenced in the configuration and assign your admin user to `ssh-users` so you do not lock yourself out:

       sudo groupadd ssh-users
       sudo groupadd PassAuthAny
       sudo groupadd PassAuthInternal
       sudo groupadd PortForwarding
       sudo groupadd GatewayListening
       sudo groupadd X11Users
       sudo usermod -aG ssh-users sysadmin

3. Validate the SSH configuration syntax before restarting the service:

       sudo sshd -t
       sudo systemctl restart ssh

4. Update your VirtualBox NAT Port Forwarding rule to map **Host Port `2220` -> Guest Port `6969`**, and connect using:

       ssh -p 2220 sysadmin@127.0.0.1

---

### Stage 3: Granular Sudo Privilege Delegation (`sudoers.d`)

Granting full `ALL=(ALL:ALL) ALL` root privileges to junior administrators, service accounts, or testing users violates the **Principle of Least Privilege**. Just like OpenSSH, `sudo` supports drop-in configuration files inside `/etc/sudoers.d/`.

#### 3.1 How the Sudoers Rule Works (`configs/sudoers/90-operator-rules`)
The included file defines two distinct privilege rules for a restricted user named `operator` (modeled on the `tester` account in our lab):

    operator ALL=(root) /usr/sbin/shutdown
    operator ALL=(sysadmin) NOPASSWD: /usr/sbin/reboot

- **Line 1:** Allows `operator` on `ALL` hosts to execute `/usr/sbin/shutdown` as the `root` user, **requiring** `operator` to enter their own password.
- **Line 2:** Allows `operator` to execute `/usr/sbin/reboot` impersonating the `sysadmin` account **without** a password prompt (`NOPASSWD:`). Any other `sudo` command will be denied.

#### 3.2 Deploy and Validate the Sudoers File
1. Create the restricted user account:

       sudo adduser operator

2. Copy `configs/sudoers/90-operator-rules` into `/etc/sudoers.d/` and enforce `0440` (read-only for owner and group) permissions:

       sudo cp configs/sudoers/90-operator-rules /etc/sudoers.d/90-operator-rules
       sudo chmod 440 /etc/sudoers.d/90-operator-rules

3. **Always verify syntax using `visudo`** (a syntax error in sudoers files can break `sudo` across the system):

       sudo visudo -cf /etc/sudoers.d/90-operator-rules

4. Test the rules by switching to `operator` (`su - operator`) and running `sudo -u sysadmin /usr/sbin/reboot`.

---

### Stage 4: Out-of-Band Emergency Serial Console Access (GRUB2 & Named Pipes)

If a misconfigured firewall (`iptables`/`ufw`) or broken network interface cuts off SSH access, administrators rely on a **Serial Console (`ttyS0`)** to access the system directly at the bootloader and kernel level.

> **Important Note on GRUB2 vs Legacy GRUB:** Older Linux tutorials reference `/boot/grub/grub.conf`. On modern Debian/Ubuntu systems using **GRUB 2**, `/boot/grub/grub.cfg` is automatically generated and explicitly warns `DO NOT EDIT THIS FILE`. All persistent modifications must be made inside **`/etc/default/grub`** followed by running `sudo update-grub`.

#### 4.1 Configure VirtualBox Serial Port (Host Pipe)
1. Shut down the Linux VM.
2. Open **VirtualBox -> VM Settings -> Serial Ports -> Port 1**.
3. Check **Enable Serial Port** and configure:
   - **Port Number:** `COM1`
   - **Port Mode:** `Host Pipe`
   - **Connect to existing pipe/socket:** *Unchecked* (so VirtualBox creates the pipe on startup)
   - **Path/Address:** `\\.\pipe\myvbox`

#### 4.2 Configure Kernel Serial Output in `/etc/default/grub`
1. Boot the Linux VM and open `/etc/default/grub` (or reference `configs/grub/grub-serial.conf`):

       sudo nano /etc/default/grub

2. Update the `GRUB_CMDLINE_LINUX_DEFAULT` line so the Linux kernel sends console output to both the main graphical/virtual screen (`tty0`) and the first serial port (`ttyS0` at `57600` baud rate):

       GRUB_CMDLINE_LINUX_DEFAULT="quiet console=tty0 console=ttyS0,57600"

3. Compile the new `/boot/grub/grub.cfg` script and reboot the machine:

       sudo update-grub
       sudo reboot

#### 4.3 Connect from Windows Host via PuTTY
1. Open **PuTTY** on your Windows 11 host (run as Administrator if pipe permissions require it).
2. Select **Connection type:** `Serial`.
3. In **Serial line**, enter: `\\.\pipe\myvbox`.
4. In **Speed**, enter: `57600`.
5. Click **Open** — you will receive a direct login prompt over the virtual serial cable completely independent of the VM's network stack.

---

### Stage 5: Web-Based Server Administration (Cockpit)

For visual telemetry (CPU/RAM graphs, disk I/O, systemd service management, and browser-based terminal access), deploy **Cockpit**.

1. Install Cockpit from the official repositories:

       sudo apt update && sudo apt install -y cockpit
       sudo systemctl enable --now cockpit.socket

2. Verify the VM IP address (`ip a` or `ifconfig`) or forward port `9090` in VirtualBox NAT settings.
3. Open your browser and navigate to:

       https://127.0.0.1:9090

4. Accept the self-signed TLS certificate warning and log in using your `sysadmin` Linux credentials.

---

### Stage 6: Hypervisor-Level Remote Desktop (VRDP)

When full graphical access is needed without installing heavy VNC/RDP servers inside the guest OS, VirtualBox provides hypervisor-level **VRDP (VirtualBox Remote Desktop Protocol)**.

1. Ensure the **Oracle VM VirtualBox Extension Pack** matching your VirtualBox version is installed on the host.
2. Open **VirtualBox -> VM Settings -> Display -> Remote Display**.
3. Check **Enable Server** and set the **Server Port** to `3389` (or another free host port).
4. On your Windows 11 host, open **Remote Desktop Connection (`mstsc.exe`)**, enter `127.0.0.1:3389`, and accept the certificate prompt to view and control the VM display.

---

## Troubleshooting & Common Issues

### 1. SSH Refuses Key Login (Asks for Password or Denies Access)
- **Cause:** Incorrect file permissions on `~/.ssh` or `authorized_keys`, or the user is not in the `AllowGroups` list defined in `90-hardening.conf`].
- **Fix:** Ensure `chmod 700 ~/.ssh` and `chmod 600 ~/.ssh/authorized_keys` are set, and confirm your user belongs to `ssh-users` (`groups sysadmin`).

### 2. VirtualBox Bridged Adapter Fails to Obtain an IP Address (DHCP Timeout)
- **Cause:** Many Wi-Fi routers and corporate/university networks drop DHCP requests coming from multiple MAC addresses over a single wireless interface.
- **Fix:** Switch the VM network adapter to **NAT** and use **Port Forwarding** rules (`Host 2222 -> Guest 22` or `Host 2220 -> Guest 6969` for SSH; `Host 9090 -> Guest 9090` for Cockpit).

### 3. PuTTY Cannot Open `\\.\pipe\myvbox`
- **Cause:** The VirtualBox VM is not currently running (the named pipe only exists while the VM is powered on), or there is a baud rate mismatch.
- **Fix:** Start the VM first, verify that `/etc/default/grub` and PuTTY both specify `57600` speed, and ensure `sudo update-grub` was executed inside the guest.

---

## License
This project is licensed under the MIT License.
