#!/bin/sh
set -euf
#
# Calomel.org
#     https://calomel.org/zfs_freebsd_root_install.html
#     FreeBSD 12.0-RELEASE ZFS Root Install script
#     zfs.sh @ Version 0.25

# NOTE: ada0 for SATA , nvd0 for PCIe M.2 NVMe

echo "# remove any old partitions on destination drive"
umount zroot || true
umount /mnt || true
zpool destroy zroot || true
gpart delete -i 2 ada0 || true
gpart delete -i 1 ada0 || true
gpart destroy -F ada0 || true

echo ""
echo "# Create zfs boot (512k) and a 220 gig root partition"
gpart create -s gpt ada0
gpart add -a 4k -s 512k -t freebsd-boot ada0
gpart add -a 4k -s 220G -t freebsd-zfs -l disk0 ada0
gpart bootcode -b /boot/pmbr -p /boot/gptzfsboot -i 1 ada0

echo ""
 # Option 1: align to 4K, ashift=12
 echo "# Align the Disks for 4K (ashift=12) and create the pool"
 gnop create -S 4096 /dev/gpt/disk0

 # Option 2: align to 8k, ashift=13
#echo "# Align the Disks for 8K (ashift=13) and create the pool"
#gnop create -S 8192 /dev/gpt/disk0

zpool create -f -o altroot=/mnt -o cachefile=/var/tmp/zpool.cache zroot /dev/gpt/disk0.nop
zpool export zroot
gnop destroy /dev/gpt/disk0.nop
zpool import -o altroot=/mnt -o cachefile=/var/tmp/zpool.cache zroot

echo ""
echo "# Set the bootfs property and set options"
zpool set bootfs=zroot zroot
zpool set listsnapshots=on zroot
zfs set logbias=throughput zroot
zfs set compression=lz4 zroot
zfs set atime=off zroot
zfs set copies=2 zroot

echo ""
echo "# Add swap space and apply options"
zfs create -V 1G zroot/swap
zfs set org.freebsd:swap=on zroot/swap
zfs set copies=1 zroot/swap

echo ""
echo "# Create a symlink to /home and fix some permissions"
cd /mnt/zroot ; ln -s usr/home home

echo ""
echo "# Set zfs to cache data for longer striped writes"
sysctl vfs.zfs.delay_min_dirty_percent=98
sysctl vfs.zfs.dirty_data_max=12884901888
sysctl vfs.zfs.dirty_data_sync_pct=95
sysctl vfs.zfs.min_auto_ashift=12
sysctl vfs.zfs.trim.txg_delay=2
sysctl vfs.zfs.txg.timeout=90
sysctl vfs.zfs.vdev.aggregation_limit=1048576
sysctl vfs.zfs.vdev.def_queue_depth=128
sysctl vfs.zfs.vdev.write_gap_limit=0
sync

echo ""
echo "# Install FreeBSD OS from *.txz memstick."
echo "# This will take a few minutes..."
cd /usr/freebsd-dist
export DESTDIR=/mnt/zroot

 # Option 1: install a 64bit os, no 32bit libs or ports or source
  for file in base.txz kernel.txz doc.txz;

 # Option 2: only install a 64bit os, no 32bit libs
 #for file in base.txz kernel.txz doc.txz ports.txz src.txz;

 # Option 3: full freebsd install
 #for file in base.txz lib32.txz kernel.txz doc.txz ports.txz src.txz;

do (cat $file | tar --unlink -xpJf - -C ${DESTDIR:-/}); done

echo ""
echo "# Copy zpool.cache to install disk."
cp /var/tmp/zpool.cache /mnt/zroot/boot/zfs/zpool.cache

echo ""
echo "# Setup ZFS root mount and boot"
echo 'zfs_enable="YES"' >> /mnt/zroot/etc/rc.conf
echo 'zfs_load="YES"' >> /mnt/zroot/boot/loader.conf
echo 'vfs.root.mountfrom="zfs:zroot"' >> /mnt/zroot/boot/loader.conf

echo ""
echo "# use gpt ids instead of gptids or disks idents"
echo 'kern.geom.label.disk_ident.enable="0"' >> /mnt/zroot/boot/loader.conf
echo 'kern.geom.label.gpt.enable="1"' >> /mnt/zroot/boot/loader.conf
echo 'kern.geom.label.gptid.enable="0"' >> /mnt/zroot/boot/loader.conf

echo ""
echo "# enable networking, pf and ssh and stop syslog from listening."
echo 'hostname="FreeBSDzfs"' >> /mnt/zroot/etc/rc.conf
echo 'ifconfig_igb0="dhcp"' >> /mnt/zroot/etc/rc.conf
echo '#ifconfig_igb0="inet 192.168.0.150 netmask 255.255.255.0 ether 00:11:22:33:44:55"' >> /mnt/zroot/etc/rc.conf
echo '#defaultrouter="192.168.0.1"' >> /mnt/zroot/etc/rc.conf
echo '#pf_enable="YES"' >> /mnt/zroot/etc/rc.conf
echo '#pflog_enable="YES"' >> /mnt/zroot/etc/rc.conf
echo 'sshd_enable="YES"' >> /mnt/zroot/etc/rc.conf
echo 'syslogd_flags="-ss"' >> /mnt/zroot/etc/rc.conf
echo 'nameserver 1.1.1.1' >> /mnt/zroot/etc/resolv.conf

echo ""
echo "# drop packets sent to closed ports."
echo 'net.inet.icmp.drop_redirect=1' >> /mnt/zroot/etc/sysctl.conf
echo 'net.inet.sctp.blackhole=2' >> /mnt/zroot/etc/sysctl.conf
echo 'net.inet.tcp.blackhole=2' >> /mnt/zroot/etc/sysctl.conf
echo 'net.inet.tcp.drop_synfin=1' >> /mnt/zroot/etc/sysctl.conf
echo 'net.inet.tcp.path_mtu_discovery=0' >> /mnt/zroot/etc/sysctl.conf
echo 'net.inet.udp.blackhole=1' >> /mnt/zroot/etc/sysctl.conf

echo ""
echo "# sshd, disable remote root logins."
echo 'PermitRootLogin no' >> /mnt/zroot/etc/ssh/sshd_config
echo 'PermitEmptyPasswords no' >> /mnt/zroot/etc/ssh/sshd_config

echo ""
echo "# /etc/rc.conf disable sendmail"
echo 'dumpdev="NO"' >> /mnt/zroot/etc/rc.conf
echo 'sendmail_enable="NONE"' >> /mnt/zroot/etc/rc.conf

echo ""
echo "# touch the /etc/fstab else freebsd will not boot properly"
touch /mnt/zroot/etc/fstab

sync
echo ""
echo "# Syncing... Install Done."
echo ""
echo "# Hint: poweroff, remove the USB drive and re-boot the machine."
echo "#       Then add a privlidged user to the 'wheel' group. You will"
echo "#       then be able to ssh in as the new user and configure the box."
echo ""
sync

#### EOF ####
