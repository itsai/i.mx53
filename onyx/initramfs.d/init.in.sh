accepted_pkgs="UPDATE_PACKAGE_NAME"
init=/linuxrc

MMC_DIR=/mnt/mmc

check_update()
{
  update_pkg=""
  for i in $accepted_pkgs
  do
      if [ "$i" = "onyx_update.upd" ] || [ "$i" = "update.upd" ]; then
          if [ -f $MMC_DIR/$i ]; then
              update_pkg=$MMC_DIR/$i
              break;
          fi
      else
          for j in `ls $MMC_DIR/$i*.upd | xargs -n1 basename`
          do
              vmax="0"
              gen=`echo $j | sed "s/$i//" | sed "s/.upd//"`
              if [[ "$gen" > "$vmax" ]]; then
                  vmax="$gen"
                  update_pkg=$MMC_DIR/$j
              fi
          done
      fi
  done

  if [ -n $update_pkg ]; then
    # Extracting files.
    echo "Extracting files..."
    disp_msg /bin/extracting.dat

    # Decrypt the update package
    aescrypt -d -p __AES_PASSWORD__ -o onyx_update.tgz $update_pkg

    # Extracting files
    tar -zvxf onyx_update.tgz
    rm onyx_update.tgz

    # Do update.
    disp_msg /bin/updating.dat
    cd onyx_update
    if [ "$REQUIRED_CUSTOMER_ID" == "" ]; then
        ./update.sh
    else
        if [ -f ./customer_id ]; then
            pkg_id=`cat ./customer_id`
            if [ $pkg_id = "$REQUIRED_CUSTOMER_ID" ]; then
                ./update.sh
            fi
        fi
    fi

    # Update complete, change display
    disp_msg /bin/booting.dat

    # Remove update directory
    cd ..
    rm -rf ./onyx_update

    # Restart device
    reboot
  else
    disp_msg /bin/no_updates.dat
  fi
}

normal_boot()
{
  # Mount real rootfs
  mount -t yaffs2 /dev/mtdblock4 /newroot

  # Check if there is a init script
  if [ -x "/newroot/${init}" ] ; then
    #Unmount all other mounts so that the ram used by
    #the initramfs can be cleared after switch_root
    umount /sys /proc

    #Switch to the new root and execute init
    exec switch_root /newroot "${init}"
  fi
}

# Mount things needed by this script
busybox mount -t proc proc /proc
busybox mount -t sysfs sysfs /sys

# Create all the symlinks to /bin/busybox
busybox --install -s

# Main entry for initramfs
echo "Entering initramfs..."

# Load code page modules.
insmod /lib/modules/nls_iso8859-1.ko
insmod /lib/modules/nls_cp437.ko

# Load SD/MMC module
insmod /lib/modules/mmc_core.ko
insmod /lib/modules/mxc_mmc.ko
insmod /lib/modules/mmc_block.ko

retry_count=0
while [ $retry_count -lt 5 ]
do
  mount -t vfat /dev/mmcblk0p1 /mnt/mmc
  if [ $? = 0 ]; then
    break
  fi
  sleep 1
  retry_count=`expr $retry_count + 1`
done

if [ $retry_count -lt 5 ]; then
  check_update
  umount /mnt/mmc
else
  mount -t vfat /dev/mmcblk0 /mnt/mmc
  if [ $? = 0 ]; then
    check_update
    umount /mnt/mmc
  else
    # No sd card in slot
    echo "Mount SD card failed"
    disp_msg /bin/no_updates.dat
  fi
fi

# Start normal boot process.
normal_boot

# Impossible to reach.
exec sh
