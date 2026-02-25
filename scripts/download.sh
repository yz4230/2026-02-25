#!/bin/bash

IMAGE_URL='https://cloud.debian.org/images/cloud/trixie/latest/debian-13-genericcloud-amd64.qcow2'
IMAGE_NAME='debian-cloud.qcow2'
wget "$IMAGE_URL" -O "$IMAGE_NAME"
