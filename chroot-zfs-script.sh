echo 'Adding ArchZFS repo to pacman...'
echo -e '
[archzfs]
Server = https://archzfs.com/$repo/x86_64' >> /etc/pacman.conf


# ArchZFS GPG keys (see https://wiki.archlinux.org/index.php/Unofficial_user_repositories#archzfs)
echo 'Updating keys...'

pacman-key -r DDF7DB817396A49B2A2723F7403BD972F75D9D76
pacman-key --lsign-key DDF7DB817396A49B2A2723F7403BD972F75D9D76

# Install base packages
echo 'Install base packages...'

pacman -Sy
 kernel_compatible_with_zfs="$(pacman -Si zfs-linux \
| grep 'Depends On' \
| sed "s|.*linux=||" \
| awk '{ print $1 }')" 
pacman -U --noconfirm https://america.archive.pkgbuild.com/packages/l/linux/linux-"${kernel_compatible_with_zfs}"-x86_64.pkg.tar.zst

# Install zfs packages
echo 'Install zfs packages...'

pacman -S --noconfirm zfs-linux zfs-utils

# Configure mkinitcpio
echo 'Configure mkinitcpio...'

sed -i 's|filesystems|zfs filesystems|' /etc/mkinitcpio.conf
mkinitcpio -P

# For physical machine, install firmware

pacman -S --noconfirm linux-firmware intel-ucode amd-ucode

# Enable internet time synchronisation:

systemctl enable systemd-timesyncd

# Set hostname
echo 'Set hostname...'

echo arch > /etc/hostname
echo -e '127.0.0.1 localhost\n::1 localhost\n127.0.1.1 arch' >> /etc/hosts

# Generate locales:

echo "en_US.UTF-8 UTF-8" >> /etc/locale.gen
locale-gen

# GRUB
# Apply GRUB workaround
echo 'Apply GRUB workaround...'

export ZPOOL_VDEV_NAME_PATH=YES

# GRUB fails to detect rpool name, hard code as "rpool"
sed -i "s|rpool=.*|rpool=rpool|"  /etc/grub.d/10_linux

# Install GRUB
echo 'Install GRUB...'

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

# Generate GRUB menu
echo 'Generate GRUB menu'

mkdir -p /boot/grub
grub-mkconfig -o /boot/grub/grub.cfg
cp /boot/grub/grub.cfg /boot/efi/archlinux/grub-bootdir/x86_64-efi/grub/grub.cfg
cp /boot/grub/grub.cfg /boot/efi/archlinux/grub-bootdir/i386-pc/grub/grub.cfg

# For both legacy and EFI booting: mirror ESP content:

espdir=$(mktemp -d)
find /boot/efi/ -maxdepth 1 -mindepth 1 -type d -print0 | xargs -t -0I '{}' cp -r '{}' "${espdir}"
find "${espdir}" -maxdepth 1 -mindepth 1 -type d -print0 | xargs -t -0I '{}' sh -vxc "find /boot/efis/ -maxdepth 1 -mindepth 1 -type d -print0 | xargs -t -0I '[]' cp -r '{}' '[]'"

# Adding user 
echo 'Adding user mk...'

 useradd -m -G root mk
 echo 'mk:1234' | chpasswd
