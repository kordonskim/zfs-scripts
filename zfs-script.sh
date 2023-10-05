# Adding zfs packages
echo 'Adding zfs packages...'

curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash

# find /dev/disk/by-id/

# wipefs -a /dev/disk/by-id/ata-Hitachi_HDS5C3020BLE630_MCE7215P035WTN

echo 'Setting variables...'

DISK='/dev/disk/by-id/ata-Hitachi_HDS5C3020BLE630_MCE7215P035WTN'
MNT=/mnt
SWAPSIZE=16
RESERVE=1

# create partitions
echo 'Creating partitions...'

partition_disk () {
 local disk="${1}"
#  blkdiscard -f "${disk}" || true

 parted --script --align=optimal  "${disk}" -- \
 mklabel gpt \
 mkpart EFI 2MiB 1GiB \
 mkpart bpool 1GiB 5GiB \
 mkpart rpool 5GiB -$((SWAPSIZE + RESERVE))GiB \
 mkpart swap  -$((SWAPSIZE + RESERVE))GiB -"${RESERVE}"GiB \
 mkpart BIOS 1MiB 2MiB \
 set 1 esp on \
 set 5 bios_grub on \
 set 5 legacy_boot on

 partprobe "${disk}"
}

for i in ${DISK}; do
   partition_disk "${i}"
done

# Load ZFS kernel module
echo 'Load ZFS kernel module...'

modprobe zfs

# create zfs boot
echo 'Create bpool...'

zpool create -d \
    -f \
    -o feature@async_destroy=enabled \
    -o feature@bookmarks=enabled \
    -o feature@embedded_data=enabled \
    -o feature@empty_bpobj=enabled \
    -o feature@enabled_txg=enabled \
    -o feature@extensible_dataset=enabled \
    -o feature@filesystem_limits=enabled \
    -o feature@hole_birth=enabled \
    -o feature@large_blocks=enabled \
    -o feature@lz4_compress=enabled \
    -o feature@spacemap_histogram=enabled \
    -o ashift=12 \
    -o autotrim=on \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=lz4 \
    -O devices=off \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/boot \
    -R "${MNT}" \
    bpool \
    $(for i in ${DISK}; do
       printf '%s ' "${i}-part2";
      done)

# create rpool      
echo 'Create rpool...'

zpool create \
    -f \
    -o ashift=12 \
    -o autotrim=on \
    -R "${MNT}" \
    -O acltype=posixacl \
    -O canmount=off \
    -O compression=zstd \
    -O dnodesize=auto \
    -O normalization=formD \
    -O relatime=on \
    -O xattr=sa \
    -O mountpoint=/ \
    rpool \
   $(for i in ${DISK}; do
      printf '%s ' "${i}-part3";
     done)

#  create rpool system container
echo 'Create rpool system container...'

zfs create \
 -o canmount=off \
 -o mountpoint=none \
rpool/archlinux     

# Create system datasets, manage mountpoints with mountpoint=legacy
echo 'Create system datasets, manage mountpoints with mountpoint=legacy...'

zfs create -o canmount=noauto -o mountpoint=/  rpool/archlinux/root
zfs mount rpool/archlinux/root
zfs create -o mountpoint=legacy rpool/archlinux/home
mkdir "${MNT}"/home
mount -t zfs rpool/archlinux/home "${MNT}"/home
# zfs create -o mountpoint=legacy  rpool/archlinux/var
# zfs create -o mountpoint=legacy rpool/archlinux/var/lib
# zfs create -o mountpoint=legacy rpool/archlinux/var/log
zfs create -o mountpoint=none bpool/archlinux
zfs create -o mountpoint=legacy bpool/archlinux/root
mkdir "${MNT}"/boot
mount -t zfs bpool/archlinux/root "${MNT}"/boot
# mkdir -p "${MNT}"/var/log
# mkdir -p "${MNT}"/var/lib
# mount -t zfs rpool/archlinux/var/lib "${MNT}"/var/lib
# mount -t zfs rpool/archlinux/var/log "${MNT}"/var/log

# Format and mount ESP
echo 'Format and mount ESP...'

for i in ${DISK}; do
 mkfs.vfat -n EFI "${i}"-part1
 mkdir -p "${MNT}"/boot/efis/"${i##*/}"-part1
 mount -t vfat -o iocharset=iso8859-1 "${i}"-part1 "${MNT}"/boot/efis/"${i##*/}"-part1
done

mkdir -p "${MNT}"/boot/efi
mount -t vfat -o iocharset=iso8859-1 "$(echo "${DISK}" | sed "s|^ *||"  | cut -f1 -d' '|| true)"-part1 "${MNT}"/boot/efi

# # System setup

# curl --fail-early --fail -L https://america.archive.pkgbuild.com/iso/2023.09.01/archlinux-bootstrap-x86_64.tar.gz -o rootfs.tar.gz

# curl --fail-early --fail -L https://america.archive.pkgbuild.com/iso/2023.09.01/archlinux-bootstrap-x86_64.tar.gz.sig -o rootfs.tar.gz.sig

# apk add gnupg
# gpg --auto-key-retrieve --keyserver hkps://keyserver.ubuntu.com --verify rootfs.tar.gz.sig

# ln -s "${MNT}" "${MNT}"/root.x86_64
# tar x  -C "${MNT}" -af rootfs.tar.gz root.x86_64

# # Enable community repo

# sed -i '/edge/d' /etc/apk/repositories
# sed -i -E 's/#(.*)community/\1community/' /etc/apk/repositories

# Generate fstab:
echo 'Generate fstab...'

mkdir "${MNT}"/etc
genfstab -t PARTUUID "${MNT}" \
| grep -v swap \
| sed "s|vfat.*rw|vfat rw,x-systemd.idle-timeout=1min,x-systemd.automount,noauto,nofail|" \
> "${MNT}"/etc/fstab

# Chroot

cp /etc/resolv.conf "${MNT}"/etc/resolv.conf
for i in /dev /proc /sys; do mkdir -p "${MNT}"/"${i}"; mount --rbind "${i}" "${MNT}"/"${i}"; done
chroot "${MNT}" /usr/bin/env DISK="${DISK}" bash

# Pacstrap packages to MNT
echo 'Pacstrap packages to MNT...'

pacstrap "${MNT}"  base base-devel linux linux-headers linux-firmware grub efibootmgr nano micro openssh

# # Add archzfs repo to pacman config

# pacman-key --init
# pacman-key --refresh-keys
# pacman-key --populate

# curl --fail-early --fail -L https://archzfs.com/archzfs.gpg | pacman-key -a - --gpgdir /etc/pacman.d/gnupg

# pacman-key --lsign-key --gpgdir /etc/pacman.d/gnupg DDF7DB817396A49B2A2723F7403BD972F75D9D76

# tee -a /etc/pacman.d/mirrorlist-archzfs <<- 'EOF'
# ## See https://github.com/archzfs/archzfs/wiki
# ## France
# #,Server = https://archzfs.com/$repo/$arch

# ## Germany
# #,Server = https://mirror.sum7.eu/archlinux/archzfs/$repo/$arch
# #,Server = https://mirror.biocrafting.net/archlinux/archzfs/$repo/$arch

# ## India
# #,Server = https://mirror.in.themindsmaze.com/archzfs/$repo/$arch

# ## United States
# #,Server = https://zxcvfdsa.com/archzfs/$repo/$arch
# EOF

# tee -a /etc/pacman.conf <<- 'EOF'

# #[archzfs-testing]
# #Include = /etc/pacman.d/mirrorlist-archzfs

# #,[archzfs]
# #,Include = /etc/pacman.d/mirrorlist-archzfs
# EOF

# # this #, prefix is a workaround for ci/cd tests
# # remove them
# sed -i 's|#,||' /etc/pacman.d/mirrorlist-archzfs
# sed -i 's|#,||' /etc/pacman.conf
# sed -i 's|^#||' /etc/pacman.d/mirrorlist


echo 'Copy chroot-zfs-script to /mnt...'

cp ./chroot-zfs-script.sh /mnt/root

echo 'Run chroot-zfs-script...'

arch-chroot "${MNT}" /usr/bin/env DISK="${DISK}" sh /root/chroot-zfs-script.sh

echo 'Cleanup...'

umount -Rl "${MNT}"
zpool export -a







