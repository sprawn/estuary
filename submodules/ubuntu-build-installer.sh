#!/bin/bash

set -ex

top_dir=$(cd `dirname $0`; cd ..; pwd)
version=$1 # branch or tag
build_dir=$(cd /root/$2 && pwd)

out=${build_dir}/out/release/${version}/ubuntu/
distro_dir=${build_dir}/tmp/ubuntu
workspace=${distro_dir}/installer
out_installer=${workspace}/out/images

# set mirror
. ${top_dir}/include/mirror-func.sh
set_ubuntu_mirror

mirror=${UBUNTU_MIRROR:-http://ports.ubuntu.com/ubuntu-ports}
estuary_repo=${UBUNTU_ESTUARY_REPO:-"ftp://repoftp:repopushez7411@117.78.41.188/releases/5.0/ubuntu"}
estuary_dist=${UBUNTU_ESTUARY_DIST:-estuary-5.0}
installer_src_version="20101020ubuntu451.15"

sudo apt-get update -q=2
sudo apt-get install -y debian-archive-keyring gnupg dctrl-tools bc debiandoc-sgml xsltproc libbogl-dev glibc-pic libslang2-pic libnewt-pic genext2fs e2fsprogs mklibs genisoimage dosfstools
sudo apt-get install -y grub-efi-arm64-bin mtools module-init-tools openssl xorriso bf-utf-source docbook-xml docbook-xsl cpio python-requests
sudo apt-get install -y u-boot-tools

# Find kernel abi
kernel_abi=$(apt-cache depends linux-image-estuary-arm64 | grep -m 1 Depends \
| sed -e "s/.*linux-image-//g" -e "s/-arm64//g")

echo "mirror is ${mirror}"
echo "estuary_repo is ${estuary_repo}"
echo "estuary_dist is ${estuary_dist}"
echo "installer_src_version is ${installer_src_version}"
echo "kernel_abi is ${kernel_abi}"

# Build the installer
mkdir -p ${workspace}
cd ${workspace}
rm -rf ./*
(dget ${mirror}/pool/main/d/debian-installer/debian-installer_${installer_src_version}.dsc) || true

xz -d debian-installer_*.xz
tar xvf debian-installer_*.tar
cd debian-installer-*

#sed -i 's/fshelp|//g' build/util/grub-cpmodules

## Config changes
cd build
sed -i "s/LINUX_KERNEL_ABI.*/LINUX_KERNEL_ABI = $kernel_abi/g" config/common
sed -i "s/PRESEED.*/PRESEED = default-preseed/g" config/common
sed -i "s/USE_UDEBS_FROM.*/USE_UDEBS_FROM = xenial/g" config/common
sed -i "s/KERNELVERSION =.*/KERNELVERSION = 4.12.0-500-generic/g" config/arm64.cfg
sed -i "s/KERNELMAJOR =.*/KERNELMAJOR = 4.12/g" config/arm64.cfg

# Local pkg-list (to include all udebs)
cat <<EOF > pkg-lists/local
fat-modules-\${kernel:Version}
md-modules-\${kernel:Version}
scsi-modules-\${kernel:Version}
sata-modules-\${kernel:Version}
usb-modules-\${kernel:Version}
block-modules-\${kernel:Version}
crypto-modules-\${kernel:Version}
nfs-modules-\${kernel:Version}
nic-modules-\${kernel:Version}
nic-shared-modules-\${kernel:Version}
nic-usb-modules-\${kernel:Version}
storage-core-modules-\${kernel:Version}
virtio-modules-\${kernel:Version}
fs-core-modules-\${kernel:Version}
fs-secondary-modules-\${kernel:Version}
input-modules-\${kernel:Version}
ipmi-modules-\${kernel:Version}
irda-modules-\${kernel:Version}
message-modules-\${kernel:Version}
mouse-modules-\${kernel:Version}
multipath-modules-\${kernel:Version}
parport-modules-\${kernel:Version}
plip-modules-\${kernel:Version}
ppp-modules-\${kernel:Version}
vlan-modules-\${kernel:Version}
EOF


# Set up local repo
cat <<EOF > sources.list.udeb
deb [trusted=yes] ${estuary_repo} ${estuary_dist} main/debian-installer
deb ${mirror} xenial main/debian-installer
EOF

# Default preseed to add the overlay and kernel
cat <<EOF > default-preseed
# Continue install on "no kernel modules were found for this kernel"
d-i anna/no_kernel_modules boolean true

# Skip linux-image-arm64 installation
d-i base-installer/kernel/image string none
EOF

# 1) build netboot installer
fakeroot make build_netboot

# publish netboot 
mkdir -p ${out}
(cp -f default-preseed ${out}/default-preseed.cfg)
(cd dest/netboot/ && cp -f mini.iso netboot.tar.gz ${out})

## 2) build cdrom installer
cat <<EOF > default-preseed
# Continue install on "no kernel modules were found for this kernel"
d-i anna/no_kernel_modules boolean true

# Continue install on "no installable kernels found"
d-i base-installer/kernel/skip-install boolean true
d-i base-installer/kernel/no-kernels-found boolean true

d-i pkgsel/include string wget
d-i base-installer/kernel/image string linux-image-estuary
EOF
fakeroot make build_cdrom_grub

# publish cdrom 
mkdir -p ${out_installer}
(cp -rf dest/* ${out_installer}/)
