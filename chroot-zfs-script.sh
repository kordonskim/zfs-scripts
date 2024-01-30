GRN='\033[0;32m'
NC='\033[0m'
ORG='\033[0;33m'

# Set hostname
echo -e "\n${GRN}Set hostname...${NC}\n"

echo arch > /etc/hostname
echo -e '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 arch' >> /etc/hosts

# Generate locales:
echo -e "\n${GRN}Set hostname...${NC}\n"

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen
echo 'LANG=en_US.UTF-8' > /etc/locale.conf

sudo ln -sf /usr/share/zoneinfo/America/Chicago /etc/localtime
hwclock --systohc

# Adding ArchZFS repo to pacman
echo -e "\n${GRN}Adding ArchZFS repo to pacman...${NC}\n"

echo -e '
[zfs-linux]
Server = http://kernels.archzfs.com/$repo/

[archzfs]
Server = https://archzfs.com/$repo/x86_64' >> /etc/pacman.conf


# ArchZFS GPG keys (see https://wiki.archlinux.org/index.php/Unofficial_user_repositories#archzfs)
echo -e "\n${GRN}Updating keys...${NC}\n"

pacman-key -r DDF7DB817396A49B2A2723F7403BD972F75D9D76
pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76

# Install base packages
echo -e "\n${GRN}Install base packages...${NC}\n"

sed -i 's|fsck||' /etc/mkinitcpio.conf
pacman -Sy
kernel_compatible_with_zfs="$(pacman -Si zfs-linux | grep 'Depends On' | sed "s|.*linux=||" | awk '{ print $1 }')" 
pacman -U --noconfirm https://america.archive.pkgbuild.com/packages/l/linux/linux-"${kernel_compatible_with_zfs}"-x86_64.pkg.tar.zst

# Install zfs packages
echo -e "\n${GRN}Install zfs packages...${NC}\n"

pacman -S --noconfirm zfs-linux zfs-utils

# Configure mkinitcpio
echo -e "\n${GRN}Configure mkinitcpio...${NC}\n"

sed -i 's|filesystems|zfs filesystems|' /etc/mkinitcpio.conf
mkinitcpio -P

# Setting ZFS cache
echo -e "\n${GRN}Setting ZFS cache and bootfs...${NC}\n"

mkdir -p  /etc/zfs
zpool set cachefile=/etc/zfs/zpool.cache zroot
zpool set bootfs=zroot/ROOT/arch zroot

# Generate hostid
echo -e "\n${GRN}Generate hostid...${NC}\n"

zgenhostid -f -o /etc/hostid

# Install additional packages
echo -e "\n${GRN}Install additional packages...${NC}\n"

pacman -S --noconfirm intel-ucode amd-ucode nano limine micro mc wget ansible git man-db man-pages neovim mc ripgrep fish starship sudo reflector htop btop fzf wget terminus-font btrfs-progs

# Enable services
echo -e "\n${GRN}Enable services...${NC}\n"

echo -e "[Match]\nName=eno*\n\n[Network]\nDHCP=yes" > /etc/systemd/network/en.network
chown root:systemd-network /etc/systemd/network/en.network

#echo -e "\nnameserver 1.1.1.1\nnameserver 9.9.9.9" >> /etc/resolv.conf
sed -i 's|#PasswordAuthentication|PasswordAuthentication|' /etc/ssh/sshd_config

systemctl enable systemd-timesyncd
systemctl enable systemd-networkd
systemctl enable systemd-resolved
systemctl enable sshd
systemctl enable reflector.timer
# https://wiki.archlinux.org/title/ZFS
# needed fro pools to be automatically imported at boot time
systemctl enable zfs-import-cache
systemctl enable zfs-import.target
systemctl enable zfs.target
systemctl enable zfs-mount

# systemctl enable zfs-volume-wait.service
# systemctl enable zfs-volumes.target
# systemctl enable zfs-share.service
# systemctl enable zfs-zed.service

# Edit sudoers
echo -e "\n${GRN}Edit sudoers...${NC}\n"

sed -i 's|# %wheel|%wheel|' /etc/sudoers

# # GRUB -----------------------------------------------------------
# # Apply GRUB workaround
# echo -e "\n${GRN}Apply GRUB workaround...${NC}\n"

# export ZPOOL_VDEV_NAME_PATH=YES

# # GRUB fails to detect rpool name, hard code as "rpool"
# sed -i "s|rpool=.*|rpool=rpool|" /etc/grub.d/10_linux

# # Import both bpool and rpool at boot:

# echo 'GRUB_CMDLINE_LINUX="zfs_import_dir=/dev/"' >> /etc/default/grub
# sed -i "s|loglevel=3 quiet|loglevel=3|" /etc/default/grub

# # Generate GRUB menu
# echo -e "\n${GRN}Generate GRUB menu...${NC}\n"
# -----------------------------------------------------------------

# Limine bootloader 
echo -e "\n${GRN}Limine bootloader ...${NC}\n"

mkdir -p /efi/EFI/BOOT
#cp /usr/share/limine/limine-bios.sys /boot/limine
#limine bios-install $DISK
echo -e '
TIMEOUT=3
VERBOSE=yes
DEFAULT_ENTRY=1
GRAPHICS=yes
RESOLUTION=800x600
TERM_WALLPAPER=boot:///EFI/BOOT/arch.jpeg

:Arch Linux
    PROTOCOL=efi_chainload
    IMAGE_PATH=boot:///EFI/Linux/arch-linux.efi

:ZFSBootMenu
    PROTOCOL=efi_chainload
    IMAGE_PATH=boot:///EFI/zbm/zfsbootmenu.EFI

:Windows 11
    PROTOCOL=efi_chainload
    IMAGE_PATH=boot:///EFI/Microsoft/Boot/bootmgfw.efi
    #IMAGE_PATH=guid://1eac5b9f-1a50-4bf5-8b02-9449c1dd085b/EFI/Microsoft/Boot/bootmgfw.efi
    #IMAGE_PATH=hdd://2:1/EFI/

#:Arch Linux
#       PROTOCOL=linux
#       KERNEL_PATH=boot:///vmlinuz-linux
#       CMDLINE=root=ZFS=zpool/ROOT/arch rw  loglevel=3 zfs_import_dir=/dev/
#       MODULE_PATH=boot:///intel-ucode.img
#       MODULE_PATH=boot:///initramfs-linux.img
      ' > /efi/EFI/BOOT/limine.cfg

cp /usr/share/limine/BOOTX64.EFI /efi/EFI/BOOT/
efibootmgr --create --disk $DISK --part 1 --loader '\EFI\BOOT\BOOTX64.EFI' --label 'Limine' --unicode

# ZFSBootMenu bootloader 
echo -e "\n${GRN}ZFSBootMenu bootloader  bootloader ...${NC}\n"

mkdir -p /efi/EFI/zbm
wget https://get.zfsbootmenu.org/latest.EFI -O /efi/EFI/zbm/zfsbootmenu.EFI
efibootmgr --disk $DISK --part 1 --create --label "ZFSBootMenu" --loader '\EFI\zbm\zfsbootmenu.EFI' --unicode "spl_hostid=$(hostid) zbm.timeout=3 zbm.prefer=zroot zbm.import_policy=hostid"
zfs set org.zfsbootmenu:commandline="noresume init_on_alloc=0 rw spl.spl_hostid=$(hostid)" zroot/ROOT

# Adding user 
echo -e "\n${GRN}Adding user mk...${NC}\n"

# groupadd sudo
useradd -m -G root,users,sys,adm,log,scanner,power,rfkill,video,storage,optical,lp,audio,wheel mk

echo -e "\n${ORG}Changing password for mk:${NC}\n"
passwd mk
echo -e "\n${ORG}Changing password for root:${NC}\n"
passwd root

# # Install yay
# echo -e "\n${GRN}Install yay...${NC}\n"

# su mk
# cd /home/mk && mkdir repo && cd repo && git clone https://aur.archlinux.org/yay.git && cd yay && makepkg -si

# HyprV4
# git clone https://github.com/SolDoesTech/HyprV4 

