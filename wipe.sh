
umount -R /mnt
mount | grep mnt
zpool export -a
wipefs -a -f /dev/sda
lsblk