terraform {
  required_providers {
    libvirt = {
      source = "dmacvicar/libvirt"
    }
  }
}

provider "libvirt" {
  uri = "qemu:///system"
}

locals {
  image_path = abspath("${path.module}/debian-cloud.qcow2")
  nws        = { nw1 = {}, nw2 = {}, nw3 = {}, nw4 = {}, nw5 = {} }
  vms = {
    vm01 = {
      name     = "vm01"
      networks = ["nw1"]
    }
    vm02 = {
      name     = "vm02"
      networks = ["nw1", "nw2"]
    }
    vm03 = {
      name     = "vm03"
      networks = ["nw2", "nw3", "nw5"]
    }
    vm04 = {
      name     = "vm04"
      networks = ["nw3", "nw4"]
    }
    vm05 = {
      name     = "vm05"
      networks = ["nw4"]
    }
    vm06 = {
      name     = "vm06"
      networks = ["nw5"]
    }
  }
}

resource "libvirt_volume" "vol" {
  for_each = local.vms

  name = each.value.name
  pool = "default"
  target = {
    format = {
      type = "qcow2"
    }
  }
  create = {
    content = {
      url = "file:///${local.image_path}"
    }
  }
}

resource "libvirt_cloudinit_disk" "init" {
  for_each = local.vms

  name      = "${each.value.name}-init"
  user_data = file("${path.module}/user.yaml")
  meta_data = yamlencode({
    instance_id = each.value.name
    hostname    = each.value.name
  })
}

resource "libvirt_volume" "seed" {
  for_each = local.vms

  name = "${each.value.name}-seed"
  pool = "default"
  create = {
    content = {
      url = libvirt_cloudinit_disk.init[each.key].path
    }
  }
}

resource "libvirt_network" "nw" {
  for_each = local.nws

  name      = each.key
  autostart = true
}

resource "libvirt_domain" "vm" {
  for_each = local.vms

  name        = each.value.name
  memory      = "2"
  memory_unit = "GiB"
  vcpu        = 2
  type        = "kvm"
  running     = true
  features    = { acpi = true, apic = { eoi = "on" } }
  cpu         = { mode = "host-passthrough" }
  os = {
    type         = "hvm"
    type_arch    = "x86_64"
    type_machine = "q35"
    boot_devices = [{ dev = "hd" }]
  }
  devices = {
    disks = [
      {
        device = "disk"
        driver = { name = "qemu", type = "qcow2" }
        source = { file = { file = libvirt_volume.vol[each.key].path } }
        target = { dev = "vda", bus = "virtio" }
      },
      {
        device = "cdrom"
        driver = { name = "qemu", type = "raw" }
        source = { file = { file = libvirt_volume.seed[each.key].path } },
        target = { dev = "sda", bus = "sata" }
      }
    ]
    interfaces = concat(
      [{
        source      = { network = { network = "default" } }
        model       = { type = "virtio" }
        wait_for_ip = {}
      }],
      [for nw in each.value.networks : {
        source = { network = { network = nw } }
        model  = { type = "virtio" }
      }]
    )
    consoles = [{ target = { type = "serial", port = "0" } }]
    videos   = [{ model = { type = "virtio", heads = "1", primary = "yes" } }]
  }
}

data "libvirt_domain_interface_addresses" "vm_ips" {
  for_each = libvirt_domain.vm
  domain   = each.value.name
  source   = "lease"
}

output "vm_ips" {
  value = {
    for name, iface_data in data.libvirt_domain_interface_addresses.vm_ips :
    name => try(iface_data.interfaces[0].addrs[0].addr, null)
  }
}
