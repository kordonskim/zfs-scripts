
umount -R /mnt
mount | grep mnt
swapoff -a  
zpool export -a
wipefs -a -f /dev/sda
lsblk