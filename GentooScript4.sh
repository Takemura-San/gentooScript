#!/bin/bash

export DEV=/dev/sda
export ARCHIVESITE=http://ftp.iij.ad.jp/pub/linux/gentoo/releases/amd64/autobuilds/current-stage3-amd64/
export ARCHIVEFILE=stage3-amd64-20210221T214504Z.tar.xz
export PROFILE=default/linux/amd64/17.1
export TAROPTION=J
export CPU=8
export DIR=/mnt/gentoo
export FILE=GentooScript3.2.sh

judgepartition () {
	#partition type and size of $DEV1
	
	PTYPE1=$(fdisk -l | grep ${DEV}1 | awk '{print $(NF), $(NF -1), $(NF -2)}')
	#partition type and size of $DEV2
	PTYPE2=$(fdisk -l | grep ${DEV}2 | awk '{print $(NF), $(NF -1), $(NF -2)}')
	#partition type and size of $DEV3
	PTYPE3=$(fdisk -l | grep ${DEV}3 | awk '{print $(NF), $(NF -1), $(NF -2)}')
	#partition type and size of $DEV4
	PTYPE4=$(fdisk -l | grep ${DEV}4 | awk '{print $(NF), $(NF -1) $(NF -2)}')
	#determines if necessary partition typpe and size exists.
	PFDEC= #if all the partitions exists
	if [ -n "${PTYPE1}" ] && [ -n "${PTYPE2}" ] && [ -n "${PTYPE3}" ] && [ -n "${PTYPE4}" ]; then
		PFDEC=0 #all the partitoins exist
	else
		PFDEC="" #something is missing
	fi
}
#Partion number countation
PARTITION=$(parted -s -a optimal ${DEV} -- print | cut -d' ' -f2 | egrep --only-matching '^[[:digit:]]')

while getopts n:p:h opt
do
  case $opt in
    n)
      HOSTNAME=$OPTARG
      ;;

    p)
      PASS=$OPTARG
      ;;

    h)
      h="-n=hostname, -p=password"
      ;;
  esac
done

#decision making for skpping


#determines if the computer has profile setting file
PROFILEDEC=
if [ -e /var/db/repos/gentoo/profiles/base/packages ]; then
	PROFILEDEC=0
fi

#functions
echotea () {

echo "$1" | tee -a ./install_log
echo >> ./install_log
}

judgeskip () {

	if [ -n "$1" ]; then #if $1 has any values, skip the entire block of commands
		echo -e "\033[0;36mSKIP\033[0;39;m"
	fi

}

judgeokng () {
		if [ -z "$1" ] || [ "$1" -ne 0 ] ; then #ok=1, ng=other
			echo -e "\033[0;31mNG\033[0;39m"
			exit 1
		else 
			echo -e "\033[0;32mOK\033[0;39m"
		fi

}

echo "$(date +%Y%m%d%H%M%S) ending previous installation, starting new one."

judgepartition
SWAPOFFCHECK=$(free|grep Swap|awk '{print $(NF -2)}')
MOUNTCHECK2=$(mount|grep ${DEV}2)
MOUNTCHECK4=$(mount|grep ${DEV}4)
#removing partition
echo "Preparing for Partition and Filesystem Setups" 
if [ -z "${PARTITION}" ] || [ -n "${PFDEC}" ]; then
	echo -e "\033[0;36mSKIP\033[0;39;m"
else
	if [ "${SWAPOFFCHECK}" != "0" ]; then
		swapoff ${DEV}3 >> ./install_log 2>&1
	fi
	if [ -n "${MOUNTCHECK2}" ]; then
		umount -lf ${DEV}2 >> ./install_log 2>&1
	fi
	if [ -n "${MOUNTCHECK4}" ]; then
		umount -lf ${DEV}4 >> ./install_log 2>&1
	fi
	for i in $PARTITION; do
		parted -s -a optimal $DEV rm "$i"
	done
	judgepartition
	judgeokng "${PARTITION}"
fi
echo "a\n1\nw" | fdisk -t dos $DEV  >> test.log 2>&1
parted -s -a optimal $DEV mklabel gpt  >> test.log 2>&1


#partition and filesystem setting
echotea "Setting Partition and Filesystem"
if [ -z "${PFDEC}" ]; then
	(parted -s -a optimal $DEV unit mib && \
	parted -s -a optimal $DEV -- mkpart primary 1 3 && \
	parted -s -a optimal $DEV name 1 grub && \
	parted -s -a optimal $DEV set 1 bios_grub on && \
	parted -s -a optimal $DEV -- mkpart ext4 3 131 && \
	parted -s -a optimal $DEV name 2 boot && \
	parted -s -a optimal $DEV -- mkpart mkswap 131 643 && \
	parted -s -a optimal $DEV name 3 swap && \
	parted -s -a optimal $DEV -- mkpart xfs 643 -1 && \
	parted -s -a optimal $DEV name 4 rootfs && \
	parted -s -a optimal $DEV set 2 boot on && \
	mkfs.ext2 -F -T small ${DEV}2 && \
	mkfs.ext3 -F -T small ${DEV}3 && \
	mkfs.ext4 -F -T small ${DEV}4 && \
	mkswap ${DEV}3 && \
	swapon ${DEV}3) >> ./install_log 2>&1
	judgepartition
	judgeokng "${PFDEC}"
else
	judgeskip "1"
fi

mount ${DEV}4 ${DIR} >> ./install_log 2>&1
mkdir ${DIR}/boot
mount ${DEV}2 ${DIR}/boot >> ./install_log 2>&1


#stage tarball
echotea "Downloading and unzipping stage tarball"
if [ -f  "${DIR}/${ARCHIVEFILE}" ]; then
	judgeskip "1"
else
	(cd /mnt/gentoo && \ 
	wget $ARCHIVESITE$ARCHIVEFILE && \
	tar -${TAROPTION}xpvf $ARCHIVEFILE --xattrs-include='*.*' --numeric-owner) >> ./install_log 2>&1
	EXITSTATUS=$?
	judgeokng "${EXITSTATUS}" 
fi

echotea "Setting make.conf"

PORMKCONF=/etc/portage/make.conf

cat - << EOL > ${PORMKCONF}

COMMON_FLAGS="-O2 -pipe"
CFLAGS="${COMMON_FLAGS}"
CXXFLAGS="${COMMON_FLAGS}"
FCFLAGS="${COMMON_FLAGS}"
FFLAGS="${COMMON_FLAGS}"
USE="luks_default -qt5 -kde X gtk gnome elogind -consolekit -systemd gui handwriting-tegaki debugs emacs fcitx4 handwriting-tomoe ibus renderer test corefonts djvu fftw fontconfig fpx graphviz hdri heif jbig jpeg2k lqr lzma opencl openexr perl postscript q32 q8 raw static libs webp wmf gdk-pixbuf go staticlibs gnome"

# NOTE: This stage was built with the bindist Use flag enabled
PORTDIR="/var/db/repos/gentoo"
DISTDIR="/var/cache/distfiles"
PKGDIR="/var/cache/binpkgs"

# This sets the language of build output to English.
# Please keep this setting intact when reporting bugs.
LC_MESSAGES=C

MAKEOPTS="-j${CPU}"

EOL

cp --dereference /etc/resolv.conf /mnt/gentoo/etc/

#chroot 1/2
echotea "Changing Root 1/2"
SYS_PART="sys dev proc"
# need log output
for PART in ${SYS_PART}
do
	if [ $(mount |grep /mnt/gentoo/${PART} |wc -l) -eq 0 ];then
	  case $PART in
			"sys")
        mount --rbind /sys /mnt/gentoo/sys &&
        mount --make-rslave /mnt/gentoo/sys
				judgeokng $?
				;;
			"dev")
        mount --rbind /dev /mnt/gentoo/dev &&
        mount --make-rslave /mnt/gentoo/dev
				judgeokng $?
				;;
      "proc")	  
        mount --type proc /proc /mnt/gentoo/proc
				judgeokng $?
				;;
		esac
	else
  	judgeskip 1
  fi
done

cat - << EOS > ${DIR}/${FILE}

#!/bin/bash

DIR2=/
FILE2=./install_log

[ -f \${FILE2} ] && rm \${FILE2}

echotea () {
  echo "\$1" | tee -a \${FILE2}
  echo >> \${FILE2}
}

print_status () {
    case "\$1" in
		  "0")
			  echo -e "\033[0;32mOK\033[0;39m"
				;;
		  "[0-9]*")
			  echo -e "\033[0;31mNG\033[0;39m"
				;;
		  "skip")
		    echo -e "\033[0;36mSKIP\033[0;39;m"
				;;
		esac
}
			
set -e

#chroot 2/2
echotea "Changing Root 2/2"

#TimeZone setting
echotea "Setting Timezone"
cp /usr/share/zoneinfo/Asia/Tokyo /etc/localtime
print_status 0

#portage setting
FILE=/var/db/repos/gentoo/metadata/timestamp.x 
[ -f "\${FILE}" ] && SYNC_DATE=\$(cat \${FILE} |cut -f1 -d' ')
echotea "Setting Portage"
if [ -z "\${SYNC_DATE}" ] || [ \$(expr \$(date +%s) - \${SYNC_DATE}) -gt 86400 ]; then
  emerge-webrsync >> \${DIR2}/install2_log 2>&1
	EXIT_STATUS=\$?
else
  EXIT_STATUS="skip"
fi
print_status "${EXIT_STATUS}"

echotea "Select profile"
[ -f /etc/make.profile ] &&
(rm /etc/make.profile &&
ln -s /usr/portage/profiles/\$profile /etc/make.profile) >> \${DIR2}/install2_log 2>&1
print_status 0

#world emerge
echotea "Emerging @World"
chmod 644 /var/db/repos/gentoo/profiles/thirdpartymirrors
emerge --verbose --update --deep --newuse @world >> \${DIR2}/install2_log 2>&1
print_status \$?


#locale setting
echotea "Setting Locale"
(emerge --config sys-libs/timezone-data &&
echo en_US. UTF-8 > /etc/locale.gen &&
echo ja_JP. UTF-8 >> /etc/locale.gen &&
locale-gen &&
echo 'LANG="ja_JP.utf8"' > /etc/env.d/02locale &&
echo 'LC_COLLATE="C"' >> /etc/env.d/02locale &&
env-update) >> \${DIR2}/install2_log 2>&1
print_status 0


#emerge kernel sources
echotea "Emerging Kernel-Sources"
(emerge sys-kernel/gentoo-sources &&
[ -d /usr/src/linux ] &&
emerge gentoo-sources) >> \${DIR2}/install2_log 2>&1
print_status 0

echotea "Emerging genkernel"
(env-update &&
echo "=sys-kernel/linux-firmware-20201218 linux-fw-redistributable no-source-code" > /etc/portage/package.license &&
echo "-3" | etc-update &&
emerge --autounmask-write sys-kernel/genkernel) >> \${DIR2}/install2_log 2>&1
print_status 0

#fstab setting
echotea "Setting fstab"
(echo -e "\${DEV}2\t/boot\text4\tnoauto,noatime\t1 2" > /etc/fstab &&
echo -e "\${DEV}3\tnone\tswap\tsw\t0 0" >> /etc/fstab &&
echo -e "\${DEV}4\t/\txfs\tnoatime\t0 1" >> /etc/fstab &&
echo -e "/dev/cdrom\t/mnt/cdrom\tauto\tnoauto,user\t0 0" >> /etc/fstab) >> \${DIR2}/install2_log 2>&1
print_status 0

#genkernel-all
echotea "Compiling kernel sources"
genkernel all >> \${DIR2}/install2_log 2>&1
print_status 0

#hostname setting
echotea "Setting Hostname"
echo 'hostname="\${HOSTNAME:-hostname}"' > /etc/conf.d/hostname >> \${DIR2}/install2_log 2>&1
print_status 0

#network setting
echotea "Setting Network"
(NET_FILE2=/etc/conf.d/net
emerge --noreplace net-misc/netifrc &&
echo 'dns_domain_lo="homenetwork"' > \${NET_FILE2} &&
echo 'config_eth0="dhcp"' >> \${NET_FILE2} &&
ln -s /etc/init.d/net.lo /etc/init.d/net.eth0 &&
rc-update add net.eth0 default) >> \${DIR2}/install2_log 2>&1
print_status 0

#passwprd setting
echotea "Setting Password"
echo -e "\${PASS}\n\${PASS}" | passwd >> \${DIR2}/install2_log 2>&1
print_status 0

#sshd dhcpcd setting
echotea "Setting sshd and dhcpcd"
(rc-update add sshd default &&
emerge net-misc/dhcpcd) >> \${DIR2}/install2_log 2>&1
print_status 0

#bootloader setting
echotea "Setting Bootloader"
(emerge --verbose sys-boot/grub:2 &&
grub-install \$DEV &&
grub-mkconfig -o /boot/grub/grub.cfg) >> \${DIR2}/install2_log 2>&1
print_status 0

EOS

echotea "install system" 
[ -f "${DIR}/${FILE}" ] && \
	(chmod +x ${DIR}/${FILE} 
	chroot /mnt/gentoo /${FILE}) >> ./install_log 2>&1
