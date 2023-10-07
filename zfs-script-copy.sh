GRN='\033[0;32m'
NC='\033[0m'


# Adding zfs packages
echo -e "\n${GRN}Adding zfs packages...${NC}\n"

curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash

# find /dev/disk/by-id/

# mount -o remount,size=1G /run/archiso/cowspace    
# wipefs -a /dev/disk/by-id/ata-Hitachi_HDS5C3020BLE630_MCE7215P035WTN

echo -e "\n${GRN}Setting variables...${NC}\n"

DISK='/dev/disk/by-id/ata-Hitachi_HDS5C3020BLE630_MCE7215P035WTN'
MNT=/mnt
SWAPSIZE=16
RESERVE=1

# create partitions
echo -e "\n${GRN}Creating partitions...${NC}\n"

partition_disk () {
 local disk="${1}"
#  blkdiscard -f "${disk}" || true

 parted --script --align=optimal  "${disk}" -- \
 mklabel gpt \
 mkpart BIOS 1MiB 2MiB \
 mkpart EFI 2MiB 1GiB \
 mkpart bpool 1GiB 5GiB \
 mkpart rpool 5GiB -$((SWAPSIZE + RESERVE))GiB \
 mkpart swap  -$((SWAPSIZE + RESERVE))GiB -"${RESERVE}"GiB \
 set 1 bios_grub on \
 set 1 legacy_boot on \
 set 2 esp on \
 set 4 swap on
 
 partprobe "${disk}"
}

for i in ${DISK}; do
   partition_disk "${i}"
done

# Setup swap
echo -e "\n${GRN}Setup swap...${NC}\n"

for i in ${DISK}; do
   mkswap "${i}-part5"
   swapon "${i}-part5"
done

# Load ZFS kernel module
echo -e "\n${GRN}Load ZFS kernel module...${NC}\n"

modprobe zfs

# create zfs boot
echo -e "\n${GRN}Create bpool...${NC}\n"

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
       printf '%s ' "${i}-part3";
      done)

# create rpool      
echo -e "\n${GRN}Create rpool...${NC}\n"

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
      printf '%s ' "${i}-part4";
     done)

#  create rpool system container
echo -e "\n${GRN}Create rpool system container...${NC}\n"

zfs create -o canmount=off -o mountpoint=none rpool/archlinux     

# Create system datasets
echo -e "\n${GRN}Create system datasets...${NC}\n"

zfs create -o canmount=noauto -o mountpoint=/  rpool/archlinux/root
zfs mount rpool/archlinux/root
zfs create -o mountpoint=/home rpool/archlinux/home
zfs mount -a
zfs create -o mountpoint=none bpool/archlinux
zfs create -o mountpoint=legacy bpool/archlinux/root
mkdir "${MNT}"/boot
mount -t zfs bpool/archlinux/root "${MNT}"/boot

# Format and mount ESP
echo -e "\n${GRN}Format and mount ESP...${NC}\n"

for i in ${DISK}; do
 mkfs.vfat -n EFI "${i}"-part2
 mkdir -p "${MNT}"/boot/efis/"${i##*/}"-part2
 mount -t vfat -o iocharset=iso8859-1 "${i}"-part2 "${MNT}"/boot/efis/"${i##*/}"-part2
done

mkdir -p "${MNT}"/boot/efi
mount -t vfat -o iocharset=iso8859-1 "$(echo "${DISK}" | sed "s|^ *||"  | cut -f1 -d' '|| true)"-part2 "${MNT}"/boot/efi

# Generate fstab:
echo -e "\n${GRN}Generate fstab...${NC}\n"

mkdir "${MNT}"/etc
genfstab -t PARTUUID "${MNT}" \
| grep -v swap \
| sed "s|vfat.*rw|vfat rw,x-systemd.idle-timeout=1min,x-systemd.automount,noauto,nofail|" \
> "${MNT}"/etc/fstab

# # Chroot
# for i in /dev /proc /sys; do mkdir -p "${MNT}"/"${i}"; mount --rbind "${i}" "${MNT}"/"${i}"; done
# chroot "${MNT}" /usr/bin/env DISK="${DISK}" bash

# Pacstrap packages to MNT
echo -e "\n${GRN}Pacstrap packages to /mnt...${NC}\n"

pacstrap "${MNT}" base base-devel linux linux-headers linux-firmware grub efibootmgr nano micro openssh ansible git
cp /etc/resolv.conf "${MNT}"/etc/resolv.conf

echo -e "\n${GRN}Copy chroot-zfs-script to /mnt...${NC}\n"

cp ./chroot-zfs-script.sh /mnt/root

echo -e "\n${GRN}Run chroot-zfs-script...${NC}\n"

arch-chroot "${MNT}" /usr/bin/env DISK="${DISK}" sh /root/chroot-zfs-script.sh

echo -e "\n${GRN}Cleanup...${NC}\n"

rm /mnt/root/chroot-zfs-script.sh 
echo -e "\n${ORG}Run umount -Rl /mnt${NC}\n"
echo -e "\n${ORG}Run zpool export -a${NC}\n"
# umount -Rl "${MNT}"
# zpool export -a

echo -e "\n${GRN}Done...${NC}\n"