#!/bin/bash

# This script automatically installs arch linux. It's very simple and only works for rather specific situations.
# It requires networkmanager to be installed for wifi. This can be done with archiso https://wiki.archlinux.org/title/archiso
# I put this script in releng/airootfs/root and chmod +x it. I think that's all that's necessary due to the presence of .automated_script.sh in there
# If it doens't work for some reason, you can add a call to the script in .bash_profile in the image
# I use syslinux here because that's what I know and prefer
# This is designed to be used for a kiosk system, so I just do simple 50/50 partitioning for / and /home
# If you run this as-is without breakpoints enabled it will wipe /dev/sda without warning, so be careful

# Configuration Options

ETHERNET=0          # Flag to indicate if Ethernet connectivity should be used (1 for yes, 0 for no)
EFI=0               # Flag to indicate if the system uses EFI (1 for EFI, 0 for non-EFI)
STATIC=0            # Flag to indicate if a static IP should be used for the WiFi connection (1 for static, 0 for DHCP)
STATIC_IP="123.456.789.0" # The static IP address to assign if STATIC is set to 1
WIFI_SSID="XYZ"    # The SSID of the WiFi network to connect to
WIFI_PASSWORD="xyz" # The password for the WiFi network
TARGET_DISK="/dev/sda"  # The disk on which the system will be installed
#BOOT_SIZE="(2*1024*1024*1024)" # The size of the boot partition in bytes, calculated as 2 GB
HOSTNAME="x"         # The hostname to assign to the system
TIMEZONE="America/New_York" # The timezone to configure the system to use
LOCALE="en_US.UTF-8"        # The system locale
ROOT_PASSWORD="x"          # The root password
USER_NAME="x"              # The username for the primary user account to be created
USER_PASSWORD="x"          # The password for the primary user account
SSH_PASSWORD="x"           # The password to set for SSH access during installation

BREAKPOINTS=1 # Set to 1 to step through the script, 0 for fully automated

breakpoint() {
    local message=$1
    while true; do
        read -p "$message" choice
        case "$choice" in
            [Cc]* ) break;;
            [Qq]* ) echo "Script execution cancelled."; exit 1;;
            * ) echo "Please answer continue (c) or cancel (q).";;
        esac
    done
}

# if we need ssh during install we need to set a root password
# this is not the password for the installed system, just for the installer
# sshd runs by default in the arch installer so no need to start it

echo -e "$SSH_PASSWORD\n$SSH_PASSWORD" | passwd

if [ "$ETHERNET" -eq 1 ]; then
    # Ethernet probably just works
    echo "Ethernet mode selected, skipping wifi setup."
else
    # Detect wifi adapter
    wifi_adapter=$(ip addr | grep -Eo 'wlan[0-9]|wlp[0-9]s[0-9]|wlx[[:xdigit:]]{12}' | head -n 1)

    # wifi credentials
    ssid=$WIFI_SSID
    wifi_password=$WIFI_PASSWORD

    # Start NetworkManager service
    sudo systemctl start NetworkManager.service
    sleep 5

    # Rescan for wifi networks
    nmcli device wifi rescan
    sleep 5

    # Connect
    nmcli dev wifi connect "$ssid" password "$wifi_password" ifname "$wifi_adapter"
fi


if [ "$STATIC" -eq 1 ]; then
    nmcli con mod "$ssid" ipv4.addresses "$STATIC_IP"/24 ipv4.method manual

    sudo systemctl restart NetworkManager.service

    nmcli con up "$ssid"
fi



# create partitions
create_partitions() {

        local device=$TARGET_DISK
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
        ) | sfdisk $device

}
if [ "$BREAKPOINTS" -eq 1 ]; then
 breakpoint "We're about to wipe $TARGET_DISK! Press c to continue or q to cancel."
fi
create_partitions

# format partitions
mkfs.ext4 -F /dev/sda1
mkfs.ext4 -F /dev/sda2
mkfs.ext4 -F /dev/sda3

# mount paritions
mount /dev/sda2 /mnt
mkdir /mnt/boot
mkdir /mnt/home
mount /dev/sda1 /mnt/boot
mount /dev/sda3 /mnt/home

# install the system
pacstrap /mnt base linux linux-firmware xorg networkmanager xorg-server sddm lxqt breeze-icons syslinux gptfdisk sudo xorg-xinit

# The archwiki uses this command genfstab -U /mnt >> /mnt/etc/fstab
# I found it to be unreliable for automated installs
# So we write fstab manually

echo "/dev/sda1 /boot ext4 defaults 0 2" >> /mnt/etc/fstab
echo "/dev/sda2 / ext4 defaults 0 1" >> /mnt/etc/fstab
echo "/dev/sda3 /home ext4 defaults 0 2" >> /mnt/etc/fstab

# hostname and timezone
echo $HOSTNAME > /mnt/etc/hostname
ln -sf /usr/share/zoneinfo/$TIMEZONE /mnt/etc/localtime

# main configuation of the installed system
arch-chroot /mnt /bin/bash <<EOF
hwclock --systohc # set hardware clock
echo "LANG=$LOCALE" > /etc/locale.conf                      # add locale to locale.conf
sed -i "/#$LOCALE UTF-8/s/^# //" /etc/locale.gen            # add locale to local.genfstab
locale-gen                                                  # generate locales
echo -e "$ROOT_PASSWORD\n$ROOT_PASSWORD" | passwd           # set root password
chmod 755 /home                                             # make sure we have permission to write /home
useradd -m -G wheel -s /bin/bash $USER_NAME                 # add user
echo "exec startlxqt" > /home/$USER_NAME/.xinitrc           # session to autostart
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.xinitrc       # make sure we have permission to write .xinitrc
echo -e 'if [[ -z \$DISPLAY ]] && [[ \$(tty) = /dev/tty1 ]]; then\n  startx\nfi' >> /home/$USER_NAME/.bash_profile # startx auto
chown $USER_NAME:$USER_NAME /home/$USER_NAME/.bash_profile  # make sure we have permission to write .bash_profile
echo -e "$USER_PASSWORD\n$USER_PASSWORD" | passwd $USER_NAME# set user password
sed -i '/%wheel ALL=(ALL) ALL/s/^# //' /etc/sudoers         # add wheel to sudoers
syslinux-install_update -i -a -m                            # install syslinux
sed -i 's/root=\/dev\/sda3/root=\/dev\/sda2/g' /boot/syslinux/syslinux.cfg # set / to /dev/sda2
mkdir -p /etc/systemd/system/getty@tty1.service.d/          # directory for getty service
echo -e "[Service]\nExecStart=\nExecStart=-/usr/bin/agetty --autologin $USER_NAME --noclear %I $TERM" > /etc/systemd/system/getty@tty1.service.d/override.conf                          # autlogin service

EOF
if [ "$BREAKPOINTS" -eq 1 ]; then
    breakpoint "Installation is complete, continue (c) to reboot or cancel (q) for further manual configuration"
fi
#Custom setup goes here

reboot
