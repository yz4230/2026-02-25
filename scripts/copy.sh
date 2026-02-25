#!/bin/bash
set -euxo pipefail

rm debian.qcow2 || true
cp debian-cloud.qcow2 debian.qcow2
qemu-img resize debian.qcow2 +10G
