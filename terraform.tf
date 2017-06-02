#
# Author(s): Flavio Castelli <flavio@suse.com>
#            Alvaro Saurin <alvaro.saurin@suse.com>
#
# Copyright (c) 2017 SUSE LINUX GmbH, Nuernberg, Germany.
#
# All modifications and additions to the file contributed by third parties
# remain the property of their copyright owners, unless otherwise agreed
# upon. The license for this file, and modifications and additions to the
# file, is the same license as for the pristine package itself (unless the
# license for the pristine package is not an Open Source License, in which
# case the license is the MIT License). An "Open Source License" is a
# license that conforms to the Open Source Definition (Version 1.9)
# published by the Open Source Initiative.
#

#####################
# Cluster variables #
#####################

variable "libvirt_uri" {
  default     = "qemu:///system"
  description = "libvirt connection url - default to localhost"
}

variable "img_pool" {
  default     = "default"
  description = "pool to be used to store all the volumes"
}

variable "img_src" {
  type        = "string"
  default     = "http://download.suse.de/install/SUSE-CaaSP-1.0-Beta3/"
  description = "URL to the CaaSP image for KVM - see http://download.suse.de/ibs/SUSE:/SLE-12-SP2:/Update:/Products:/CASP10/images/ contents"
}

variable "img_local" {
  type        = "string"
  default     = "images/beta/caasp.qcow2"
  description = "local copy of the image"
}

variable "img_refresh" {
  default     = "true"
  description = "Try to get the latest image (true/false)"
}

variable "nodes_count" {
  default     = 2
  description = "Number of non-admin nodes to be created"
}

variable "prefix" {
  type        = "string"
  default     = "caasp_beta"
  description = "a prefix for resources"
}

variable "password" {
  type        = "string"
  default     = "linux"
  description = "password for sshing to the VMs"
}

variable "nodes_memory" {
  default     = 2048
  description = "RAM of the node expressed in bytes"
}

#######################
# Cluster declaration #
#######################

provider "libvirt" {
  uri = "${var.libvirt_uri}"
}

resource "null_resource" "local_checkout_of_caasp_image" {
  provisioner "local-exec" {
    command = "./support/tf/download-image.sh --src ${var.img_src} --refresh ${var.img_refresh} --local ${var.img_local}"
  }
}

# This is the CaaSP kvm image that has been created by IBS
resource "libvirt_volume" "base_img" {
  name      = "${basename(var.img_local)}"
  source    = "${var.img_local}"
  pool      = "${var.img_pool}"
  overwrite = "true"
  depends_on = ["null_resource.local_checkout_of_caasp_image"]
}

##############
# Admin node #
##############
resource "libvirt_volume" "admin" {
  name           = "${var.prefix}_admin.qcow2"
  pool           = "${var.img_pool}"
  base_volume_id = "${libvirt_volume.base_img.id}"
}

data "template_file" "admin_cloud_init_user_data" {
  template = "${file("cloud-init/admin.cfg.tpl")}"

  vars {
    password = "${var.password}"
  }
}

resource "libvirt_cloudinit" "admin" {
  name      = "${var.prefix}_admin_cloud_init.iso"
  pool      = "${var.img_pool}"
  user_data = "${data.template_file.admin_cloud_init_user_data.rendered}"
}

resource "libvirt_domain" "admin" {
  name      = "${var.prefix}_admin"
  memory    = "${var.nodes_memory}"
  cloudinit = "${libvirt_cloudinit.admin.id}"

  disk {
    volume_id = "${libvirt_volume.admin.id}"
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = 1
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }
}

output "ip_admin" {
  value = "${libvirt_domain.admin.network_interface.0.addresses.0}"
}

###########################
# Cluster non-admin nodes #
###########################

resource "libvirt_volume" "node" {
  name           = "${var.prefix}_node_${count.index}.qcow2"
  pool           = "${var.img_pool}"
  base_volume_id = "${libvirt_volume.base_img.id}"
  count          = "${var.nodes_count}"
}

data "template_file" "node_cloud_init_user_data" {
  template = "${file("cloud-init/node.cfg.tpl")}"

  vars {
    admin_node_ip = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password      = "${var.password}"
  }

  depends_on = ["libvirt_domain.admin"]
}

resource "libvirt_cloudinit" "node" {
  name      = "${var.prefix}_node_cloud_init.iso"
  pool      = "${var.img_pool}"
  user_data = "${data.template_file.node_cloud_init_user_data.rendered}"
}

resource "libvirt_domain" "node" {
  count      = "${var.nodes_count}"
  name       = "${var.prefix}_node_${count.index}"
  memory     = "${var.nodes_memory}"
  cloudinit  = "${libvirt_cloudinit.node.id}"
  depends_on = ["libvirt_domain.admin"]

  disk {
    volume_id = "${element(libvirt_volume.node.*.id, count.index)}"
  }

  network_interface {
    network_name   = "default"
    wait_for_lease = 1
  }

  graphics {
    type        = "vnc"
    listen_type = "address"
  }
}

output "nodes" {
  value = ["${libvirt_domain.node.*.network_interface.0.addresses.0}"]
}
