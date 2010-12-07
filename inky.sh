#!/bin/bash

STEP=0
TOTALSTEPS=6
PARTITIONS=()
HOSTNAME='archlinux'
TIMEZONE='America/Chicago'
HWCLOCK='localtime'
USELVM='no'
USELVMSNAPSHOT='no'
INTERACTIVE='yes'

# $1 = question $2 = default value
ask() {
  echo "${1}"
  read result
  if [ -z "${result}" ]; then
    result="${2}"
  fi
}

welcome() {
  echo "step ${STEP}/${TOTALSTEPS}"
  echo 'Welcome to inky the archlinux installer'
  echo 'type next to go to the next step'
  echo 'type previous to go to a previous step'
  echo 'type redo to restart the current step'
  echo 'you can type the following to go to them:'
  echo 'welcome, partition, filesystem, network, timezone, install'
}

partition() {
  echo "step ${STEP}/${TOTALSTEPS}"
  echo 'prepare partitions for archlinux'
  echo 'ex. cfdisk /dev/sda, fdisk, parted, whatever'
}

filesystem() {
  PARTITIONS=()
  echo "step ${STEP}/${TOTALSTEPS}"

  ask 'do you want to use lvm yes, or [no]' 'no'
  if [ ${result} = 'yes' ]; then
    USELVM=${result}
    ask 'do you want to use lvm snapshots yes, or [no]' 'no'
    if [ ${result} = 'yes' ]; then
      USELVMSNAPSHOT=${result}
    fi

    # need to load module that handles lvm
    modprobe dm-mod

    ask 'enter the devices/partitions you wish to use seperated by spaces [/dev/sda]' '/dev/sda'
    pvcreate ${result}

    echo "use vgcreate, vgextend, and vgdisplay to create volume groups, type exit when you're done"
    /bin/bash

    echo "use lvcreate, and lvdisplay to create logical volumes, type exit when you're done"
    /bin/bash
  fi

  while true; do
    ask 'type add to add a partition or [done]' 'done'
    if [ "x${result}" = 'xdone' ]; then
      break
    fi

    ask 'enter the device [/dev/sda1]' '/dev/sda1'
    device=${result}

    ask 'enter the filesystem type ext2, ext3, [ext4], reiserfs, jfs, xfs, nilfs, btrfs, tmpfs, swap' 'ext4'
    type=${result}

    if [ ${type} = 'swap' ]; then
      location='swap'
    else
      ask 'enter the filesystem location [/]' '/'
      location=${result}
    fi

    if [ "x${USELVM}" = 'xyes' ]; then
      ask 'is this an lvm partition [yes], no' 'yes'
      islvm=${result}
    else
      islvm='no'
    fi

    PARTITIONS+=("$device $location $type $islvm")
  done
}

network() {
  echo "step ${STEP}/${TOTALSTEPS}"
  echo 'please setup the network'
  echo 'ex. dhcpcd eth0'

  ask 'please enter the hostname [archlinux]' 'archlinux'
  HOSTNAME=${result}
}

timezone() {
  echo "step ${STEP}/${TOTALSTEPS}"
  echo 'available timezones listed under /usr/share/zoneinfo'
  ask 'enter your timezone [America/Chicago]' 'America/Chicago'
  TIMEZONE=${result}

  ask 'how should the time be stored on the hardware clock? [localtime], or utc' 'localtime'
  HWCLOCK=${result}
}

bootloader() {
  echo "step ${STEP}/${TOTALSTEPS}"

  ask 'installing bootloader, which to install; grub, [grub2], lilo, syslinux, or none?' 'grub2'
  bootloader=${result}
  ask 'where to install too? [/dev/sda]' '/dev/sda'
  grubdevice=${result}
}

install() {
  echo "step ${STEP}/${TOTALSTEPS}"

  ask 'do you want to edit configs after install, answer no only if you know what you are doing, or are a fan of russian roullette, [yes], no' 'yes'
  if [ "x${result}" = 'xno' ]; then
    INTERACTIVE='no'
  fi

  ask 'are you sure you want to continue installing? type yes if you are certain. [yes]' 'yes'
  if [ ! "${result}" = 'yes' ]; then
    return 0
  fi

  #############################################################################
  # FILESYSTEM MOUNTING
  #############################################################################
  echo 'creating and mounting filesystems...'
  for part in "$PARTITIONS"; do
    device=$(echo "$part" | awk '{ print $1 }')
    location=$(echo "$part" | awk '{ print $2 }')
    type=$(echo "$part" | awk '{ print $3 }')
    case $type in
      ext4)
        mkfs.ext4 ${device}
        mount ${device} /mnt${location}
        ;;
      ext3)
        mkfs.ext3 ${device}
        mount ${device} /mnt${location}
        ;;
      ext2)
        mkfs.ext2 ${device}
        mount ${device} /mnt${location}
        ;;
      reiserfs)
        yes | mkfs.reiserfs ${device}
        mount ${device} /mnt${location}
        ;;
      jfs)
        mkfs.jfs ${device}
        mount ${device} /mnt${location}
        ;;
      xfs)
        mkfs.xfs ${device}
        mount ${device} /mnt${location}
        ;;
      nilfs)
        mkfs.nilfs ${device}
        mount ${device} /mnt${location}
        ;;
      btrfs)
        mkfs.btrfs ${device}
        mount ${device} /mnt${location}
        ;;
      tmpfs)
        mount -t tmpfs tmpfs /mnt${location}
        ;;
      swap)
        mkswap ${device}
        swapon ${device}
        ;;
      *)
        echo "error"
        ;;
    esac
  done

  mkdir -p /mnt/{proc,sys,dev}
  mount -t proc proc /mnt/proc
  mount -t sysfs sys /mnt/sys
  mount -o bind /dev /mnt/dev

  #############################################################################
  # PACKAGE INSTALLATION
  #############################################################################
  echo 'installing system'
  cp /etc/resolv.conf /mnt/etc/
  #cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d
  # get latest mirrorlist
  wget -O /mnt/etc/pacman.d/mirrorlist http://www.archlinux.org/mirrorlist/all/

  mkdir -p /mnt/var/lib/pacman
  pacman -Sy -r /mnt
  mkdir -p /mnt/var/cache/pacman/pkg
  pacman --cachedir /mnt/var/cache/pacman/pkg -S base -r /mnt --noconfirm

  #############################################################################
  # BOOTLOADER
  #############################################################################

  rootdevice='/dev/sda1'
  bootdevice='notfound'
  # find / and /boot
  for part in "${PARTITIONS}"; do
    device=$(echo "$part" | awk '{ print $1 }')
    location=$(echo "$part" | awk '{ print $2 }')
#    type=$(echo "$part" | awk '{ print $3 }')
#    uuid=$(blkid $device -o value | head -n 1)

    if [ ${location} = '/' ]; then
      rootdevice=${device}
    fi
    if [ ${location} = '/boot' ]; then
      bootdevice=${device}
    fi
  done

  case $bootloader in
    grub2)
      pacman --cachedir /mnt/var/cache/pacman/pkg -R grub -r /mnt --noconfirm
      pacman --cachedir /mnt/var/cache/pacman/pkg -S grub2 -r /mnt --noconfirm

      chroot /mnt grub-install ${grubdevice} --no-floppy
      chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
      ;;
    syslinux)
      pacman --cachedir /mnt/var/cache/pacman/pkg -S syslinux -r /mnt --noconfirm
      mkdir /mnt/boot/syslinux
      cat /mnt/usr/lib/syslinux/mbr.bin > ${grubdevice}
      chroot /mnt extlinux --install /boot/syslinux

      # make bootable
#      sfdisk /dev/sda1 << EOF
#,,,*
#EOF
      echo ",,,*" | sfdisk ${bootdevice}
      #parted /dev/sda set 1 boot on

      #cat /mnt/usr/lib/syslinux/mbr.bin > ${grubdevice}

      bootprefix='/boot'
      if [ ! ${bootdevice} = 'notfound' ]; then
        bootprefix=''
      fi

      cat << EOF >> /mnt/boot/syslinux/syslinux.cfg
PROMPT 1
TIMEOUT 50
DEFAULT arch

LABEL arch
        LINUX ${bootprefix}/vmlinuz26
        APPEND root=${rootdevice} ro
        INITRD ${bootprefix}/kernel26.img

LABEL archfallback
        LINUX ${bootprefix}/vmlinuz26
        APPEND root=${rootdevice} ro
        INITRD ${bootprefix}/kernel26-fallback.img
EOF
      ;;
    grub)
      echo 'not supported yet'
      ;;
    lilo)
      echo 'not supported yet'
      ;;
    none)
      ;;
    *)
      echo 'error, no such bootloader'
      ;;
  esac

  #############################################################################
  # AUTOCONFIG
  #############################################################################
  echo 'autoconfig for convenience'
  sed -i "s/myhost/$HOSTNAME/" /mnt/etc/rc.conf
  sed -i "s/localtime/$HWCLOCK/" /mnt/etc/rc.conf
  sed -i "s/localhost$/localhost ${HOSTNAME}/" /mnt/etc/hosts
  sed -i "s_Canada/Pacific_${TIMEZONE}_" /mnt/etc/rc.conf
  sed -i "s_#Server = http://mirrors.kernel.org_Server = http://mirrors.kernel.org_" /mnt/etc/pacman.d/mirrorlist
  if [ "x${USELVM}" = 'xyes' ]; then
    sed -i "s/USELVM=\"no\"/USELVM=\"${USELVM}\"/" /mnt/etc/rc.conf
    sed -i 's/filesystems/lvm2 filesystems/' /mnt/etc/mkinitcpio.conf
    if [ "x${USELVMSNAPSHOT}" = 'xyes' ]; then
      sed -i 's/MODULES=""/MODULES="dm-snapshot"/' /mnt/etc/mkinitcpio.conf
    fi
  fi

  for part in "${PARTITIONS}"; do
    device=$(echo "$part" | awk '{ print $1 }')
    location=$(echo "$part" | awk '{ print $2 }')
    type=$(echo "$part" | awk '{ print $3 }')
    uuid=$(blkid $device -o value | head -n 1)

    if [ ${type} = 'tmpfs' ]; then
      echo -e "\n${type} ${location} ${type} defaults 0 0" >> /mnt/etc/fstab
    elif [${type} = 'swap' ]; then
      echo -e "\nUUID=${uuid} swap ${type} defaults 0 0" >> /mnt/etc/fstab
    elif [ ${type} = 'nilfs' ] || [ ${type} = 'btrfs' ]; then
      echo -e "\nUUID=${uuid} ${location} ${type} defaults 0 0" >> /mnt/etc/fstab # these don't support fsck yet
    else
      echo -e "\nUUID=${uuid} ${location} ${type} defaults 0 1" >> /mnt/etc/fstab
    fi
  done

  if [ ${INTERACTIVE} = 'yes' ]; then
    echo 'please edit your configs and set the password by typing passwd, type exit when you are done'
    echo 'ex. vi /etc/{fstab,rc.conf,hosts,mkinitcpio.conf,locale.gen}'
    echo 'if use lvm for boot'
    echo 'add'
    echo 'insmod lvm'
    echo 'set root=(lvm_group_name-lvm_logical_boot_partition_name)'
    echo 'to the beginning of the menuentry for grub2'
  
    chroot /mnt /bin/bash
  fi
  chroot /mnt mkinitcpio -p kernel26
  chroot /mnt locale-gen
  #echo 'set the root password, might have to type exit if you are dropped to a prompt'
  #chroot /mnt /bin/bash while passwd\; do true\; done

  #############################################################################
  # CLEANUP
  #############################################################################
  umount /mnt/{dev,sys,proc}

  for part in "$PARTITIONS"; do
    device=$(echo "${part}" | awk '{ print $1 }')

    umount ${device}
  done

  echo 'type reboot to boot into your new system'
  echo 'Enjoy Archlinux!'
}

process() {
  steps=('welcome' 'partition' 'filesystem' 'network' 'timezone' 'bootloader' 'install')
  ${steps[${STEP}]}
}

previous() {
  STEP=$(( STEP - 1 ))
  process
}

next() {
  STEP=$(( STEP + 1 ))
  process
}

redo() {
  process
}

welcome
