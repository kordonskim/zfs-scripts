#!/bin/bash
#set -e # stop scripts on any error
set -u # for erors with variables
#set -x # debug 

handle_error() {
    echo "An error occurred on line $1"
    exit 1
}

trap 'handle_error $LINENO' ERR

# find /dev/disk/by-id/
# mount -o remount,size=1G /run/archiso/cowspace    
# wipefs -a /dev/disk/by-id/ata-Hitachi_HDS5C3020BLE630_MCE7215P035WTN
# git clone https://github.com/kordonskim/zfs-scripts

GRN='\033[0;32m'
ORG='\033[0;33m'
NC='\033[0m'
BBLU='\033[1;34m'
BRED='\033[1;31m'

# Adding zfs packages
# echo -e "\n${GRN}Adding zfs packages...${NC}\n"

# curl -s https://raw.githubusercontent.com/eoli3n/archiso-zfs/master/init | bash

#Increase cowspace to half of RAM.
# echo -e "\n${GRN}Increase cowspace to half of RAM...${NC}\n"

# mount -o remount,size=50% /run/archiso/cowspace

# Setting variables
echo -e "\n${GRN}Set variables...${NC}\n"



DISK=/dev/nvme0n1
DISKEFI="${DISK}p1"
DISKSWAP="${DISK}p2"
DISKROOT="${DISK}p3"
MNT=/mnt
SWAPSIZE=4
ZFSPOOL=zroot

echo -e "DISK=${ORG}$DISK${NC}"
echo -e "DISKEFI=${ORG}$DISKEFI${NC}"
echo -e "DISKSWAP=${ORG}$DISKSWAP${NC}"
echo -e "DISKROOT=${ORG}$DISKROOT${NC}"
echo -e "MNT=${ORG}$MNT${NC}"
echo -e "SWAPSIZE=${ORG}$SWAPSIZE${NC}"
echo -e "ZFSPOOL=${ORG}$ZFSPOOL${NC}"
echo

read -p "Would you like to continue (yY)? " -n 1 -r
echo    # (optional) move to a new line
if [[ ! $REPLY =~ ^[Yy]$ ]]
then
    [[ "$0" = "$BASH_SOURCE" ]]&& echo "Exiting the script per user request."  && exit 1 || return 1 # handle exits from shell or function but don't exit interactive shell
fi

echo -e "Disk: $DISK, Mnt: $MNT, Swap: $SWAPSIZE"

echo -e "\n${GRN}Wiping disk {$DISK}...${NC}\n"
wipefs -a -f $DISK
sgdisk --zap-all $DISK

# Create partitions
echo -e "\n${GRN}Create partitions...${NC}\n"

# sgdisk -n 1:0:+2M -t 1:EF02 $DISK
sgdisk -n 1:1M:+2048M -t 1:EF00 $DISK
sgdisk -n 2:0:+${SWAPSIZE}G -t 2:8200 $DISK
sgdisk -n 3:0:0 -t 3:BF00 $DISK

# Swap setup
echo -e "\n${GRN}Swap setup...${NC}\n"

mkswap $DISKSWAP
swapon $DISKSWAP


# Load ZFS kernel module
echo -e "\n${GRN}Load ZFS kernel module...${NC}\n"

modprobe zfs

# # create zfs boot
# echo -e "\n${GRN}Create bpool...${NC}\n"

# zpool create -d \
#     -f \
#     -o feature@async_destroy=enabled \
#     -o feature@bookmarks=enabled \
#     -o feature@embedded_data=enabled \
#     -o feature@empty_bpobj=enabled \
#     -o feature@enabled_txg=enabled \
#     -o feature@extensible_dataset=enabled \
#     -o feature@filesystem_limits=enabled \
#     -o feature@hole_birth=enabled \
#     -o feature@large_blocks=enabled \
#     -o feature@lz4_compress=enabled \
#     -o feature@spacemap_histogram=enabled \
#     -o ashift=12 \
#     -o autotrim=on \
#     -O acltype=posixacl \
#     -O canmount=off \
#     -O compression=lz4 \
#     -O devices=off \
#     -O normalization=formD \
#     -O relatime=on \
#     -O xattr=sa \
#     -O mountpoint=/boot \
#     -R "${MNT}" \
#     bpool \
#     $(for i in ${DISK}; do
#        printf '%s ' "${i}-part3";
#       done)

# Create zroot     
echo -e "\n${GRN}Create $ZFSPOOL...${NC}\n"

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
    $ZFSPOOL $DISKROOT

# Create system and user datasets
echo -e "\n${GRN}Create system and user datasets...${NC}\n"

zfs create -o mountpoint=none ${ZFSPOOL}/ROOT
zfs create -o canmount=noauto -o mountpoint=/ ${ZFSPOOL}/ROOT/arch
zfs create -o mountpoint=/home ${ZFSPOOL}/home
# zfs create -o canmount=noauto -o mountpoint=/  rpool/archlinux/root

zpool export ${ZFSPOOL}
zpool import -N -R /mnt ${ZFSPOOL}
# zfs load-key -L prompt zroot # Enter your pool passphrase after that command
zfs mount ${ZFSPOOL}/ROOT/arch
zfs mount ${ZFSPOOL}/home

# zfs create -o mountpoint=none bpool/archlinux
# zfs create -o mountpoint=/boot bpool/archlinux/root

zfs list

# Format and mount ESP
echo -e "\n${GRN}Format and mount ESP...${NC}\n"

mkfs.vfat -F 32 $DISKEFI

mkdir -p ${MNT}/efi
mount $DISKEFI ${MNT}/efi

# Pacstrap packages to MNT
echo -e "\n${GRN}Pacstrap packages to ${MNT}...${NC}\n"

pacstrap "${MNT}" base base-devel linux linux-headers linux-firmware efibootmgr openssh

# Generate fstab:
echo -e "\n${GRN}Generate fstab...${NC}\n"

    # mkdir "${MNT}"/etc
genfstab -U -p "${MNT}" >> "${MNT}"/etc/fstab

# remove rpool and bpool mounts form fstab
sed -i "/${ZFSPOOL}/d" ${MNT}/etc/fstab
    # sed -i '/bpool/d' "${MNT}"/etc/fstab

# remove first empty lines from fstab
sed -i '/./,$!d' ${MNT}/etc/fstab

cat "${MNT}"/etc/fstab

# Copy local files to /mnt
echo -e "\n${GRN}Copy local files to ${MNT}...${NC}\n"

# cp /etc/hostid "${MNT}"/etc
cp /etc/resolv.conf "${MNT}"/etc/resolv.conf
cp /etc/pacman.conf "${MNT}"/etc/pacman.conf

# Copy chroot-zfs-script to /mnt
echo -e "\n${GRN}Copy chroot-zfs-script to ${MNT}...${NC}\n"

cp ./chroot-zfs-script.sh /mnt/root

# Run chroot-zfs-script
echo -e "\n${BBLU}Run chroot-zfs-script...${NC}\n"

arch-chroot "${MNT}" /usr/bin/env DISK="${DISK}" ZFSPOOL="${ZFSPOOL}" sh /root/chroot-zfs-script.sh

# Cleanup
echo -e "\n${GRN}Cleanup...${NC}\n"

rm /mnt/root/chroot-zfs-script.sh 

echo -e "\n${BRED}Run swapoff -a${NC}"
echo -e "\n${BRED}Run umount -Rl /mnt${NC}"
echo -e "\n${BRED}Run zpool export -a${NC}"
# swapoff -a
# umount -Rl "${MNT}"
# zpool export -a

echo -e "\n${GRN}Done...${NC}\n"