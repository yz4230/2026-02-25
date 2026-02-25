#!/bin/bash

# generate ssh_config
terraform output -json vm_ips | jq -r 'to_entries[] | "Host \(.key)\n  HostName \(.value)\n  User debian\n  IdentityFile id\n"' >ssh_config

# generate inventory.ini
echo "[vms]" >inventory.ini
terraform output -json vm_ips | jq -r 'to_entries[] | "\(.key)"' >>inventory.ini
