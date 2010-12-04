#!/bin/bash

STEP=0
PARTITIONS=()
HOSTNAME='archlinux'
TIMEZONE='America/Chicago'

# $1 = question
# $2 = default value
ask() {
  echo "${1}"
  read result
  if [ -e "${input}" ]; then
    result="${2}"
  fi
}

welcome() {
  echo "step ${STEP}/5"
  echo 'Welcome to inky the archlinux installer'
  echo 'type next to go to the next step'
  echo 'type previous to go to a previous step'
  echo 'type redo to restart the current step'
  echo 'you can type the following to go to them:'
  echo 'welcome, partition, filesystem, network, timezone, install'
}

partition() {
  echo "step ${STEP}/5"
  echo 'prepare partitions for archlinux'
  echo 'ex. cfdisk /dev/sda'
}

filesystem() {
  echo "step ${STEP}/5"
  echo 'create filesystems and mount under /mnt'
  echo 'ex. mkfs.ext4 /dev/sda1 ; mount /dev/sda1 /mnt'

  while true; do
    ask 'type add to add a partition or [done]' 'done'
    if [ $result = 'done' ]; then
      break
    fi

    ask 'enter the device [/dev/sda1]' '/dev/sda1'
    device=${result}

    ask 'enter the filesystem type [ext4]' 'ext4'
    type=${result}

    ask 'enter the filesystem location [/]' '/'
    location=${result}

    PARTITIONS+=("$device $location $type")
  done
}

network() {
  echo "step ${STEP}/5"
  echo 'please setup the network'
  echo 'ex. dhcpcd eth0'

  ask 'please enter the hostname [archlinux]' 'archlinux'
  HOSTNAME=${result}
}

timezone() {
  echo "step ${STEP}/5"
  echo 'available timezones listed under /usr/share/zoneinfo'
  ask 'enter your timezone [America/Chicago]' 'America/Chicago'
  TIMEZONE=${result}
}

install() {
  echo "step ${STEP}/5"

  ask 'are you sure you want to continue? type yes if you are certain. [yes]' 'yes'
  if [ ! ${result} = 'yes' ]; then
    return 0
  fi

  echo 'creating filesystems...'
  for part in "$PARTITIONS"; do
    device=$(echo "$part" | awk '{ print $1 }')
    location=$(echo "$part" | awk '{ print $2 }')
    type=$(echo "$part" | awk '{ print $3 }')
    case $type in
      ext4)
        mkfs.ext4 $device
        ;;
      ext3)
        mkfs.ext3 $device
        ;;
      ext2)
        mkfs.ext2 $device
        ;;
      *)
        echo "error"
        ;;
    esac

    mount $device /mnt${location}
  done

  mkdir -p /mnt/var/lib/pacman
  pacman -Sy -r /mnt
  mkdir -p /mnt/var/cache/pacman/pkg
  pacman --cachedir /mnt/var/cache/pacman/pkg -S base -r /mnt --noconfirm

  cp /etc/resolv.conf /mnt/etc/
  #cp /etc/pacman.d/mirrorlist /mnt/etc/pacman.d
  # get latest mirrorlist
  wget -O /mnt/etc/pacman.d/mirrorlist http://www.archlinux.org/mirrorlist/all/

  mount -t proc proc /mnt/proc
  mount -t sysfs sys /mnt/sys
  mount -o bind /dev /mnt/dev

  # set some default configs for convenience
  sed -i "s/myhost/$HOSTNAME/" /mnt/etc/rc.conf
  sed -i "s/localhost$/localhost ${HOSTNAME}/" /mnt/etc/hosts
  sed -i "s_Canada/Pacific_${TIMEZONE}_" /mnt/etc/rc.conf
  sed -i "s_#Server = http://mirrors.kernel.org_Server = http://mirrors.kernel.org_" /mnt/etc/pacman.d/mirrorlist

  for part in "${PARTITIONS}"; do
    device=$(echo "$part" | awk '{ print $1 }')
    location=$(echo "$part" | awk '{ print $2 }')
    type=$(echo "$part" | awk '{ print $3 }')
    uuid=$(blkid $device -o value | head -n 1)

    echo -e "\nUUID=${uuid} ${location} ${type} defaults 0 1" >> /mnt/etc/fstab
  done

  echo 'please edit your configs, type exit when you are done'
  echo 'ex. vi /etc/{fstab,rc.conf,hosts,mkinitcpio.conf,locale.gen}'
  chroot /mnt /bin/bash
  chroot /mnt mkinitcpio -p kernel26
  chroot /mnt locale-gen
  echo "set the root password"
  chroot /mnt passwd

  #############################################################################
  # BOOTLOADER
  #############################################################################
  ask 'installing bootloader, which to install [grub2], or syslinux?' 'grub2'
  bootloader=${result}
  ask 'where to install too? [/dev/sda]' '/dev/sda'
  grubdevice=${result}
  case $bootloader in
    grub2)
      # gettext needed for grub-mkconfig
      pacman --cachedir /mnt/var/cache/pacman/pkg -S grub2 gettext -r /mnt --noconfirm

      chroot /mnt grub-install ${grubdevice} --no-floppy
      chroot /mnt grub-mkconfig -o /boot/grub/grub.cfg
      ;;
    syslinux)
      pacman --cachedir /mnt/var/cache/pacman/pkg -S syslinux -r /mnt --noconfirm
      mkdir /mnt/boot/syslinux
      extlinux --install /mnt/boot/syslinux

      # make bootable
      sfdisk /dev/sda1 << EOF
,,,*
EOF
      #parted set /dev/sda1 boot on

      cat /mnt/usr/lib/syslinux/mbr.bin > ${grubdevice}
      cat << EOF
PROMPT 1
TIMEOUT 50
DEFAULT arch

LABEL arch
        LINUX /vmlinuz26
        APPEND root=/dev/sda1 ro
        INITRD /kernel26.img

LABEL archfallback
        LINUX /vmlinuz26
        APPEND root=/dev/sda1 ro
        INITRD /kernel26-fallback.img
EOF
>> /mnt/boot/syslinux/syslinux.cfg
      ;;
    *)
      echo 'error, no such bootloader'
      ;;
  esac

  #############################################################################
  # CLEANUP
  #############################################################################
  umount /mnt/{dev,sys,proc}

  for part in "$PARTITIONS"; do
    device=$(echo "${part}" | awk '{ print $1 }')

    umount ${device}
  done

  echo "type reboot to boot into your new system"
  echo "Enjoy Archlinux!"
}

process() {
  steps=(welcome partition filesystem network timezone install)
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
