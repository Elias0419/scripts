#!/bin/bash

# This script automates the installation of Arch Linux
# The script is integrated into the installer using Archiso (https://wiki.archlinux.org/title/archiso)
# It requires NetworkManager in the the ISO to enable nmcli commands
# The script is stored in releng/airootfs/root, made executable, and invoked via the 'script=' kernel command line parameter in releng/syslinux/archiso_sys-linux.cfg
# Syslinux is used for booting because its simple and I like it
# This script is tailored specifically for my point of sale, but could be modified for other simple kiosk installations

# Warning: Running this script with breakpoints disabled will erase /dev/sda without warning


# Configuration Options

ETHERNET=0          # Flag whether Ethernet connectivity will be used during install, 1 for true
#EFI=0               # Not implemented
STATIC=0            # Flag for whether static IP should be used for the wifi connection, 1 for true
STATIC_IP="123.456.789.0" # The static IP address to assign if STATIC is set to 1
WIFI_SSID="XYZ"    # The SSID of the wifi network to connect to
WIFI_PASSWORD="xyz" # The password for the wifi network
TARGET_DISK="/dev/sda"  # The disk on which the system will be installed
HOSTNAME="x"         # The hostname to assign to the system
TIMEZONE="America/New_York" # timezone
LOCALE="en_US.UTF-8"        # locale
ROOT_PASSWORD="x"          # The root password
USER_NAME="x"              # The username for the primary user account to be created
USER_PASSWORD="x"        # The password for the primary user account
TOGGLE_SSH=0              # Boolean for whether we set a SSH password, 1 for true
SSH_PASSWORD="x"           # The password to set for SSH access during installation
SERVICE_FILE="/mnt/etc/systemd/system/installer_run_once.service"
HAS_RUN="/has_run"

BREAKPOINTS=0 # Set to 1 to step through the script, 0 for fully automated

# if [ "$BREAKPOINTS" -eq 0 ]; then
#     read -p "WARNING: We are in fully automatic mode! If you don't know why you're here or what you're doing, say no! Continue? (yes/no): " confirm
#     [[ $confirm != "yes" ]] && exit 1
# fi


breakpoint() {
    local message=$1
    while true; do
        read -p "$message" choice
        case "$choice" in
            [Cc]* ) break;;
            [Qq]* ) echo "Script execution cancelled."; exit 1;;  # touch /mnt/has_run;
            * ) echo "Please answer continue (c) or cancel (q).";;
        esac
    done
}

create_partitions() {

        local device=$TARGET_DISK
        # this is 2 gigs for /boot.
        local boot_part=$((2*1024*1024*1024))
        local total_size_bytes=$(cat /sys/block/${device##*/}/size)
        local sector_size=$(cat /sys/block/${device##*/}/queue/hw_sector_size)
        local total_size=$((total_size_bytes*sector_size))
        local remaining_size=$((total_size - boot_part))

        local half_remaining=$((remaining_size / 2))
        local boot_part_sectors=$((boot_part / sector_size))
        local half_remaining_sectors=$((half_remaining / sector_size))

        (
        echo ",${boot_part_sectors},L"
        echo ",${half_remaining_sectors},L"
        echo ",,L"
        ) | sfdisk $device # write the partitions

}

# check if we've run before
if mount /dev/sda2 /mnt; then

    if [ -f /mnt"$HAS_RUN" ]; then
        echo "Installation already completed."
        echo "Please press ENTER to reboot and remove the installation medium."
        read -p ""
        umount /mnt
        reboot
        exit 0
    fi
    umount /mnt

fi

# if we need ssh during install we need to set a root password
# (this is only for the installer, the installed system will use $ROOT_PASSWORD)
if [ "$TOGGLE_SSH" -eq 1 ]; then
    echo -e "$SSH_PASSWORD\n$SSH_PASSWORD" | passwd
fi

# connect to the internet
if [ "$ETHERNET" -eq 1 ]; then
    # Ethernet probably "just works"
    echo ""
else
    # Detect wifi adapter. The regex seems pretty reliable, but I haven't tested it thoroughly
    wifi_adapter=$(ip addr | grep -Eo 'wlan[0-9]|wlp[0-9]s[0-9]|wlx[[:xdigit:]]{12}' | head -n 1)

    ssid=$WIFI_SSID
    wifi_password=$WIFI_PASSWORD

    systemctl start NetworkManager.service
    sleep 5

    nmcli device wifi rescan
    sleep 5

    nmcli dev wifi connect "$ssid" password "$wifi_password" ifname "$wifi_adapter"
fi


if [ "$STATIC" -eq 1 ]; then
    nmcli con mod "$ssid" ipv4.addresses "$STATIC_IP"/24 ipv4.method manual

    systemctl restart NetworkManager.service
    sleep 5
    nmcli con up "$ssid"
fi

if [ "$BREAKPOINTS" -eq 1 ]; then
 breakpoint "At this point we are connected to the internet and ssh is ready. Exit the script now (q) to do a manual installation or press c to continue"
fi

if [ "$BREAKPOINTS" -eq 1 ]; then
 breakpoint "We're about to wipe $TARGET_DISK! Press c to continue or q to cancel."
fi

# create partitions
create_partitions

# format partitions
mkfs.ext4 -F /dev/sda1
mkfs.ext4 -F /dev/sda2
mkfs.ext4 -F /dev/sda3

# mount partitions
mount /dev/sda2 /mnt
mkdir /mnt/boot
mkdir /mnt/home
mount /dev/sda1 /mnt/boot
mount /dev/sda3 /mnt/home

# install the system
yes | pacman-key --init
yes | pacman-key --populate archlinux
pacstrap /mnt base linux linux-firmware xorg networkmanager xorg-server sddm lxqt breeze-icons syslinux gptfdisk sudo xorg-xinit

# fstab is written manually because genfstab is not reliable
echo "/dev/sda1 /boot ext4 defaults 0 2" >> /mnt/etc/fstab
echo "/dev/sda2 / ext4 defaults 0 1" >> /mnt/etc/fstab
echo "/dev/sda3 /home ext4 defaults 0 2" >> /mnt/etc/fstab

# hostname and timezone
echo $HOSTNAME > /mnt/etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /mnt/etc/localtime

if [ "$BREAKPOINTS" -eq 1 ]; then
 breakpoint "At this point the system is installed, without a bootloader or basic configuration. The next part does those things. Exit now (q) to do this part manually or c to continue. "
fi

# get the mac address
mac_address=$(ip link show $wifi_adapter | grep -Po 'link/ether \K[^ ]+')

# copy network stuff to the installed system
mkdir -p /mnt/etc/NetworkManager/system-connections

    cat <<EOF > /mnt/etc/NetworkManager/system-connections/$ssid.nmconnection
[connection]
id=$ssid
type=wifi
mac-address=$mac_address
permissions=

[wifi]
mode=infrastructure
ssid=$ssid

[wifi-security]
key-mgmt=wpa-psk
psk=$wifi_password

[ipv4]
method=auto

[ipv6]
method=auto
EOF



chmod 600 /mnt/etc/NetworkManager/system-connections/$ssid.nmconnection

# set up the rigs installer to run on the next boot
cp /root/rigs_pos_installer.sh /mnt/home
chmod +x /mnt/home/rigs_pos_installer.sh
    cat <<EOF > $SERVICE_FILE
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

# main configuation of the installed system
arch-chroot /mnt /bin/bash <<EOF
hwclock --systohc # set hardware clock
echo "LANG=$LOCALE" > /etc/locale.conf                      # add locale to locale.conf
sed -i "/#$LOCALE UTF-8/s/^# //" /etc/locale.gen            # add locale to locale.gen
locale-gen                                                  # generate locales
echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd           # set root password
chmod 755 /home                                             # make sure we have permission to write /home
useradd -m -G wheel -s /bin/bash $USER_NAME                 # add user
echo "exec startlxqt" > /home/$USER_NAME/.xinitrc           # session to autostart
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xinitrc       # set .xinitrc ownership
echo -e 'if [[ -z \$DISPLAY ]] && [[ \$(tty) = /dev/tty1 ]]; then\n  startx\nfi' >> /home/$USER_NAME/.bash_profile # startx auto
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.bash_profile  # set .bash_profile ownership
echo -e "$USER_PASSWORD\n$USER_PASSWORD" | passwd $USER_NAME# set user password
sed -i 's/^# *%wheel ALL=(ALL:ALL) ALL/%wheel ALL=(ALL:ALL) ALL/' /etc/sudoers # add wheel to sudoers
sed -i '$ a\rigs ALL=(ALL) ALL' /etc/sudoers # add rigs to sudoers
syslinux-install_update -i -a -m                            # install syslinux
sed -i 's/root=\/dev\/sda3/root=\/dev\/sda2/g' /boot/syslinux/syslinux.cfg # set / to /dev/sda2
mkdir -p /etc/systemd/system/getty@tty1.service.d/          # directory for getty service
echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $USER_NAME --noclear %I $TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf #autologin
systemctl enable NetworkManager.service # enable networkmanager so we have a connection on boot
systemctl enable installer_run_once.service # enable the installer to run on next boot
EOF
if [ "$BREAKPOINTS" -eq 1 ]; then
    breakpoint "Installation is complete, continue (c) to reboot or cancel (q) for further manual configuration."
fi

touch /mnt"$HAS_RUN"

reboot
