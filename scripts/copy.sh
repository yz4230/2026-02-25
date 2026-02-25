#!/bin/bash
set -euxo pipefail

rm alpine.qcow2 || true
cp alpine-nocloud.qcow2 alpine.qcow2
qemu-img resize alpine.qcow2 +10G
virt-edit -a alpine.qcow2 /boot/extlinux.conf -e 's/TIMEOUT 100/TIMEOUT 1/'
virt-edit -a alpine.qcow2 /boot/extlinux.conf -e 's/PROMPT 1/PROMPT 0/'

rm seed.iso || true
cloud-localds seed.iso user.yaml meta.yaml
