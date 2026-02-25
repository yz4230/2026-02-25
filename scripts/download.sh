#!/bin/bash

IMAGE_URL='https://dl-cdn.alpinelinux.org/alpine/v3.23/releases/cloud/nocloud_alpine-3.23.3-x86_64-bios-tiny-r0.qcow2'
IMAGE_NAME='alpine-nocloud.qcow2'
wget "$IMAGE_URL" -O "$IMAGE_NAME"
