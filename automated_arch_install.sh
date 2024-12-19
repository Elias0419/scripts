#!/bin/bash

###############################################################################
# Automated Arch Linux Installation Script
#
# This script automates the Arch Linux installation process onto a specified
# target disk, partitioning it, setting up a base system, and configuring
# network and user accounts. It is integrated into an ArchISO environment and
# is intended for a fully-automated kiosk or point-of-sale system setup.
#
# WARNING:
#   Running this script as-is will erase the contents of the specified target 
#   disk (/dev/sda by default) without prompting. Ensure you know what 
#   you're doing and have appropriate backups.
#
# REQUIREMENTS:
#   - Archiso environment with NetworkManager and nmcli available.
#   - Run as root.
#
# DISCLAIMER:
#   This script is released into the public domain. Use it at your own risk.
#
# CONFIGURATION:
#   Adjust the variables in the "Configuration Options" section as needed.
###############################################################################

set -euo pipefail

# Configuration Options
ETHERNET=0                 # Use Ethernet during install (0 = No, 1 = Yes)
STATIC=0                   # Use static IP (0 = No, 1 = Yes)
STATIC_IP="123.456.789.0"  # Static IP address (if STATIC=1)
WIFI_SSID="XYZ"            # WiFi SSID
WIFI_PASSWORD="xyz"        # WiFi Password
TARGET_DISK="/dev/sda"     # Target disk for installation
HOSTNAME="x"               # Hostname
TIMEZONE="America/New_York"# Timezone
LOCALE="en_US.UTF-8"       # Locale
ROOT_PASSWORD="x"          # Root password
USER_NAME="x"              # Primary user account name
USER_PASSWORD="x"          # Primary user account password
TOGGLE_SSH=0               # 1 = set SSH password for root during install
SSH_PASSWORD="x"           # SSH password if TOGGLE_SSH=1
SERVICE_FILE="/mnt/etc/systemd/system/installer_run_once.service"
HAS_RUN="/has_run"

###############################################################################
# Safety Checks
###############################################################################

# Ensure the script is run as root
if [[ $EUID -ne 0 ]]; then
    echo "ERROR: This script must be run as root." >&2
    exit 1
fi

# Check if required commands are available
for cmd in sfdisk mkfs.ext4 mount umount pacstrap arch-chroot nmcli ip; do
    if ! command -v "$cmd" &>/dev/null; then
        echo "ERROR: '$cmd' is not available. Please ensure it's installed." >&2
        exit 1
    fi
done

# Check that the target disk exists
if [[ ! -b "$TARGET_DISK" ]]; then
    echo "ERROR: Target disk $TARGET_DISK does not exist or is not a block device." >&2
    exit 1
fi

###############################################################################
# Functions
###############################################################################

# Simple breakpoint function for debugging if needed
breakpoint() {
    local message="$1"
    while true; do
        read -rp "$message [c=continue/q=quit]: " choice
        case "$choice" in
            [Cc]* ) break;;
            [Qq]* ) echo "Script execution cancelled."; exit 1;;
            * ) echo "Please answer 'c' or 'q'.";;
        esac
    done
}

create_partitions() {
    # This creates 3 partitions:
    #   1: /boot (2 GiB)
    #   2: / (half of the remaining space)
    #   3: /home (remaining space)
    local device="$TARGET_DISK"
    local boot_size=$((2*1024*1024*1024))  # 2GiB in bytes
    local total_size_bytes
    local sector_size
    local total_size
    local remaining_size
    local half_remaining
    local boot_part_sectors
    local half_remaining_sectors

    total_size_bytes=$(cat "/sys/block/${device##*/}/size")
    sector_size=$(cat "/sys/block/${device##*/}/queue/hw_sector_size")
    total_size=$((total_size_bytes*sector_size))
    remaining_size=$((total_size - boot_size))
    half_remaining=$((remaining_size / 2))
    boot_part_sectors=$((boot_size / sector_size))
    half_remaining_sectors=$((half_remaining / sector_size))

    # Using sfdisk to partition
    
    (
        echo ",${boot_part_sectors},L"
        echo ",${half_remaining_sectors},L"
        echo ",,L"
    ) | sfdisk "$device"
}

format_partitions() {
    mkfs.ext4 -F "${TARGET_DISK}1"
    mkfs.ext4 -F "${TARGET_DISK}2"
    mkfs.ext4 -F "${TARGET_DISK}3"
}

mount_partitions() {
    mount "${TARGET_DISK}2" /mnt
    mkdir -p /mnt/boot
    mkdir -p /mnt/home
    mount "${TARGET_DISK}1" /mnt/boot
    mount "${TARGET_DISK}3" /mnt/home
}

install_base_system() {
    yes | pacman-key --init
    yes | pacman-key --populate archlinux
    pacstrap /mnt base linux linux-firmware xorg networkmanager xorg-server sddm lxqt breeze-icons syslinux gptfdisk sudo xorg-xinit
}

write_fstab() {
    {
        echo "${TARGET_DISK}1 /boot ext4 defaults 0 2"
        echo "${TARGET_DISK}2 /     ext4 defaults 0 1"
        echo "${TARGET_DISK}3 /home ext4 defaults 0 2"
    } >> /mnt/etc/fstab
}

check_first_run() {
    # If /mnt/has_run exists, we consider installation done and reboot
    if mount "${TARGET_DISK}2" /mnt; then
        if [[ -f "/mnt$HAS_RUN" ]]; then
            echo "Installation already completed."
            echo "Press ENTER to reboot and remove the installation medium."
            read -r
            umount /mnt
            reboot
            exit 0
        fi
        umount /mnt
    fi
}

check_ssh() {
    if [[ "$TOGGLE_SSH" -eq 1 ]]; then
        echo -e "${SSH_PASSWORD}\n${SSH_PASSWORD}" | passwd
    fi
}

connect_to_the_internet() {
    systemctl start NetworkManager.service
    sleep 5

    if [[ "$ETHERNET" -eq 1 ]]; then
        # Ethernet likely just works if cable is connected and DHCP is enabled
        echo "Using Ethernet for network connectivity."
    else
        # Detect a WiFi adapter
        wifi_adapter=$(ip addr | grep -Eo 'wlan[0-9]|wlp[0-9]s[0-9]|wlx[[:xdigit:]]{12}' | head -n 1)
        if [[ -z "$wifi_adapter" ]]; then
            echo "ERROR: No WiFi adapter detected." >&2
            exit 1
        fi

        # Attempt to connect to WiFi
        nmcli device wifi rescan
        sleep 5
        nmcli dev wifi connect "$WIFI_SSID" password "$WIFI_PASSWORD" ifname "$wifi_adapter" || {
            echo "ERROR: Failed to connect to WiFi network '$WIFI_SSID'." >&2
            exit 1
        }

        if [[ "$STATIC" -eq 1 ]]; then
            nmcli con mod "$WIFI_SSID" ipv4.addresses "$STATIC_IP"/24 ipv4.method manual
            systemctl restart NetworkManager.service
            sleep 5
            nmcli con up "$WIFI_SSID"
        fi

        # Retrieve MAC address
        mac_address=$(ip link show "$wifi_adapter" | grep -Po 'link/ether \K[^ ]+')

        # Copy network configuration into the installed system
        mkdir -p /mnt/etc/NetworkManager/system-connections
        cat <<EOF > /mnt/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection
[connection]
id=$WIFI_SSID
type=wifi
mac-address=$mac_address
permissions=

[wifi]
mode=infrastructure
ssid=$WIFI_SSID

[wifi-security]
key-mgmt=wpa-psk
psk=$WIFI_PASSWORD

[ipv4]
method=auto

[ipv6]
method=auto
EOF

        chmod 600 "/mnt/etc/NetworkManager/system-connections/$WIFI_SSID.nmconnection"
    fi
}

write_hostname_and_timezone() {
    echo "$HOSTNAME" > /mnt/etc/hostname
    ln -sf "/usr/share/zoneinfo/$TIMEZONE" /mnt/etc/localtime
}

write_rigs_installer() {
    if [[ ! -f /root/rigs_pos_installer.sh ]]; then
        echo "WARNING: /root/rigs_pos_installer.sh not found. System will install without it."
    else
        cp /root/rigs_pos_installer.sh /mnt/home
        chmod +x /mnt/home/rigs_pos_installer.sh
    fi

    cat <<EOF > "$SERVICE_FILE"
[Unit]
Description=Run Once Installation Task
Wants=network-online.target
After=network-online.target

[Service]
Type=oneshot
ExecStartPre=/usr/bin/sleep 10
ExecStart=/home/rigs_pos_installer.sh
RemainAfterExit=yes

[Install]
WantedBy=multi-user.target
EOF
}

configure_the_system() {
    arch-chroot /mnt /bin/bash <<EOF
    set -euo pipefail
    hwclock --systohc
    echo "LANG=$LOCALE" > /etc/locale.conf
    sed -i "/#$LOCALE UTF-8/s/^# //" /etc/locale.gen
    locale-gen
    echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd root
    chmod 755 /home
    useradd -m -G wheel -s /bin/bash $USER_NAME
    echo "exec startlxqt" > /home/$USER_NAME/.xinitrc
    chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xinitrc
    echo -e 'if [[ -z \$DISPLAY ]] && [[ \$(tty) = /dev/tty1 ]]; then\n  startx\nfi' >> /home/$USER_NAME/.bash_profile
    chown $USER_NAME:$USER_NAME /home/$USER_NAME/.bash_profile
    echo -e "$USER_PASSWORD\n$USER_PASSWORD" | passwd $USER_NAME
    sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers
    sed -i '$ a\'"$USER_NAME ALL=(ALL) ALL" /etc/sudoers
    syslinux-install_update -i -a -m
    sed -i 's/root=\/dev\/sda3/root=\/dev\/sda2/g' /boot/syslinux/syslinux.cfg
    mkdir -p /etc/systemd/system/getty@tty1.service.d/
    echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $USER_NAME --noclear %I \$TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf
    systemctl enable NetworkManager.service
    systemctl enable installer_run_once.service || true
EOF
}

###############################################################################
# Main Script Execution
###############################################################################

check_first_run
create_partitions
format_partitions
mount_partitions
check_ssh
connect_to_the_internet
install_base_system
write_fstab
write_hostname_and_timezone
write_rigs_installer
configure_the_system
touch "/mnt$HAS_RUN"

echo "Installation complete. System will now reboot."
reboot
