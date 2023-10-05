umount -R /mnt
zpool export -a
wipefs -a -f /dev/sda
lsblk