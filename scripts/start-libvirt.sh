#!/bin/bash
set -euxo pipefail

./copy.sh

cp alpine.qcow2 seed.iso /var/lib/libvirt/images/

virt-install \
  --name alpine01 \
  --ram 2048 \
  --vcpus 2 \
  --os-variant alpinelinux3.21 \
  --disk path=/var/lib/libvirt/images/alpine.qcow2 \
  --disk path=/var/lib/libvirt/images/seed.iso,device=cdrom \
  --import \
  --network network=default \
  --nographics
