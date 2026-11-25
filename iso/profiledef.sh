#!/usr/bin/env bash
# shellcheck disable=SC2034

iso_name="soraos"
iso_label="SORAOS_$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y%m)"
iso_publisher="SoraPlatform"
iso_application="SoraOS Live Desktop"
iso_version="$(date --date="@${SOURCE_DATE_EPOCH:-$(date +%s)}" +%Y.%m.%d)"
install_dir="soraos"
arch="x86_64"
buildmodes=('iso')
bootmodes=('bios.syslinux'
           'uefi.systemd-boot')
pacman_conf="pacman.conf"
airootfs_image_type="squashfs"
airootfs_image_tool_options=('-comp' 'xz' '-Xbcj' 'x86' '-b' '1M' '-Xdict-size' '1M')
kernel_params_x86_64="cow_spacesize=4G systemd.firstboot=no"
# Keep this a plain assignment: mkarchiso sources profiledef.sh from inside a
# function, and `declare -A` here would make the array function-local.
file_permissions=(
  ["/etc/sudoers.d"]="0:0:750"
  ["/etc/sudoers.d/10-sora-live"]="0:0:440"
  # mkarchiso copies airootfs with --no-preserve=mode, so executables must be
  # listed here or they land in the image as 0644.
  ["/usr/local/bin/livecd-sound"]="0:0:755"
  ["/usr/local/bin/soraos-airootfs-setup"]="0:0:755"
)
