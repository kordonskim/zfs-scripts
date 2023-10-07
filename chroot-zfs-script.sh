GRN='\033[0;32m'
NC='\033[0m'
ORG='\033[0;33m'

echo -e "\n${GRN}Adding ArchZFS repo to pacman...${NC}\n"

echo -e '
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
kernel_compatible_with_zfs="$(pacman -Si zfs-linux \
| grep 'Depends On' \
| sed "s|.*linux=||" \
| awk '{ print $1 }')" 
pacman -U --noconfirm https://america.archive.pkgbuild.com/packages/l/linux/linux-"${kernel_compatible_with_zfs}"-x86_64.pkg.tar.zst

# Install zfs packages
echo -e "\n${GRN}Install zfs packages...${NC}\n"

pacman -S --noconfirm zfs-linux zfs-utils

# Configure mkinitcpio
echo -e "\n${GRN}Configure mkinitcpio...${NC}\n"

sed -i 's|filesystems|zfs filesystems|' /etc/mkinitcpio.conf
mkinitcpio -P

# For physical machine, install firmware

pacman -S --noconfirm intel-ucode amd-ucode

# Enable services
echo -e "\n${GRN}Enable services...${NC}\n"

echo -e "[Match]\nName=eno*\n\n[Network]\nDHCP=yes" > /etc/systemd/network/20-wired.network
echo -e "\nnameserver 1.1.1.1\nnameserver 9.9.9.9" >> /etc/resolv.conf
sed -i 's|#PasswordAuthentication|PasswordAuthentication|' /etc/ssh/sshd_config

systemctl enable systemd-timesyncd
systemctl enable systemd-networkd
systemctl enable sshd

# Set hostname
echo -e "\n${GRN}Set hostname...${NC}\n"

echo arch > /etc/hostname
echo -e '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 arch' >> /etc/hosts

# Generate locales:

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# GRUB
# Apply GRUB workaround
echo -e "\n${GRN}Apply GRUB workaround...${NC}\n"

export ZPOOL_VDEV_NAME_PATH=YES

# GRUB fails to detect rpool name, hard code as "rpool"
sed -i "s|rpool=.*|rpool=rpool|" /etc/grub.d/10_linux

# Install GRUB
echo -e "\n${GRN}Install GRUB...${NC}\n"

mkdir -p /boot/efi/archlinux/grub-bootdir/i386-pc/
mkdir -p /boot/efi/archlinux/grub-bootdir/x86_64-efi/
for i in ${DISK}; do
 grub-install --target=i386-pc --boot-directory /boot/efi/archlinux/grub-bootdir/i386-pc/  "${i}"
done
grub-install --target x86_64-efi --boot-directory /boot/efi/archlinux/grub-bootdir/x86_64-efi/ --efi-directory /boot/efi --bootloader-id archlinux --removable
if test -d /sys/firmware/efi/efivars/; then
   grub-install --target x86_64-efi --boot-directory /boot/efi/archlinux/grub-bootdir/x86_64-efi/ --efi-directory /boot/efi --bootloader-id archlinux
fi

# Import both bpool and rpool at boot:

echo 'GRUB_CMDLINE_LINUX="zfs_import_dir=/dev/"' >> /etc/default/grub
sed -i "s|loglevel=3 quiet|loglevel=3|" /etc/default/grub

# Generate GRUB menu
echo -e "\n${GRN}Generate GRUB menu...${NC}\n"

mkdir -p /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg
cp /boot/grub/grub.cfg /boot/efi/archlinux/grub-bootdir/x86_64-efi/grub/grub.cfg
cp /boot/grub/grub.cfg /boot/efi/archlinux/grub-bootdir/i386-pc/grub/grub.cfg

# For both legacy and EFI booting: mirror ESP content:

espdir=$(mktemp -d)
find /boot/efi/ -maxdepth 1 -mindepth 1 -type d -print0 | xargs -t -0I '{}' cp -r '{}' "${espdir}"
find "${espdir}" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -t -0I '{}' sh -vxc "find /boot/efis/ -maxdepth 1 -mindepth 1 -type d -print0 | xargs -t -0I '[]' cp -r '{}' '[]'"

# Adding user 
echo -e "\n${GRN}Adding user mk...${NC}\n"

# groupadd sudo
useradd -m -G root,wheel mk

echo -e "\n${ORG}Changing password for mk:${NC}\n"
passwd mk
echo -e "\n${ORG}Changing password for root:${NC}\n"
passwd root

