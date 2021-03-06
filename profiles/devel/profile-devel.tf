#####################
# Variables
#####################

# some directories
# (leaving this dirs empty will skip any copies)

variable "salt_dir" {
  default     = ""
  description = "Salt directory to copy to the Admin Node (leave empty for skipping the copy)"
}

variable "resources_dir" {
  default     = "resources"
  description = "a directory (with {admin,nodes} subdirs) with stuff to copy to the machines"
}

variable "manifests_dir" {
  default     = ""
  description = "Manifests directory to copy to the Admin Node (leave empty for skipping the copy)"
}

variable "pillar" {
  default     = ""
  description = "extra pillar variables as a space-separated list (ie, 'e2e=true dashboard=10.17.15.1')"
}

# an extra repo
# (leaving empty for not adding extra repos)

variable "repo_url" {
  default     = ""
  description = "an extra repository to add"
}

variable "repo_name" {
  default     = "devel-profile-repo"
  description = "the name given to this repository"
}

# assign roles

variable "assign_roles" {
  default     = "true"
  description = "Assign roles to the machines"
}

variable "default_role" {
  default = "kube-minion"
  description = "the default role to assign to VMs"
}

variable "roles" {
  default = {
    "0" = "kube-master"
  }
  description = "some special roles for some specific VMs"
}

# some behaviors...

variable "activate" {
  default     = "true"
  description = "run the activation in the Admin Node"
}

variable "orchestrate" {
  default     = "false"
  description = "orchestratate the cluster once the VMs are instantiated"
}

##############################
# copy resources to the admin
##############################

resource "null_resource" "copy_resources_admin" {

  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf /tmp/caasp",
    ]
  }

  provisioner "file" {
    source      = "${pathexpand(var.resources_dir)}/common"
    destination = "/tmp/caasp"
  }

  provisioner "file" {
    source      = "${pathexpand(var.resources_dir)}/admin"
    destination = "/tmp/caasp"
  }

  # fix permissions, add the tools dir to the path
  provisioner "remote-exec" {
    inline = [
      "chmod 755 /tmp/caasp/caaspctl /tmp/caasp/*.sh /tmp/caasp/*/*.sh &>/dev/null || /bin/true",
      "echo 'export PATH=$PATH:/tmp/caasp:/tmp/caasp/admin' >> /root/.bashrc",
    ]
  }
}

##############################
# copy resources to the nodes
##############################
resource "null_resource" "copy_resources_nodes" {
  count      = "${var.nodes_count}"
  connection {
    host     = "${element(libvirt_domain.node.*.network_interface.0.addresses.0, count.index)}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "rm -rf /tmp/caasp",
    ]
  }

  provisioner "file" {
    source      = "${pathexpand(var.resources_dir)}/common"
    destination = "/tmp/caasp"
  }

  provisioner "file" {
    source      = "${pathexpand(var.resources_dir)}/nodes"
    destination = "/tmp/caasp"
  }

  # fix permissions, add the tools dir to the path
  provisioner "remote-exec" {
    inline = [
      "chmod 755 /tmp/caasp/caaspctl /tmp/caasp/*.sh /tmp/caasp/*/*.sh &>/dev/null || /bin/true",
      "echo 'export PATH=$PATH:/tmp/caasp:/tmp/caasp/nodes' >> /root/.bashrc",
    ]
  }
}

resource "null_resource" "copy_resources" {
  depends_on = ["null_resource.copy_resources_admin", "null_resource.copy_resources_nodes"]
}

##########################
# Copy Salt to admin node
##########################

resource "null_resource" "copy_salt" {
  # this will not be run at all when salt_dir==''
  count      = "${signum(length(var.salt_dir))}"
  depends_on = ["null_resource.copy_resources_admin"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl rw on",
      "rm -rf /usr/share/salt/kubernetes",
    ]
  }

  provisioner "file" {
    source      = "${pathexpand(var.salt_dir)}"
    destination = "/usr/share/salt/kubernetes"
  }
}

###################################
# Copy manifests to the admin node
###################################

resource "null_resource" "copy_manifests" {
  # this will not be run at all when manifests_dir==''
  count      = "${signum(length(var.manifests_dir))}"
  depends_on = ["null_resource.copy_resources_admin"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl rw on",
      "rm -rf /usr/share/caasp-container-manifests",
    ]
  }

  provisioner "file" {
    source      = "${pathexpand(var.manifests_dir)}"
    destination = "/usr/share/caasp-container-manifests"
  }
}

#####################
# Role assignation
#####################

data "template_file" "role_grain" {
  count    = "${var.nodes_count}"
  template = "roles:\n- $${role}"
  vars {
    role = "${lookup(var.roles, count.index, var.default_role)}"
  }
}

resource "null_resource" "set_role_grain" {
  count      = "${var.assign_roles ? var.nodes_count : 0}"
  connection {
    host     = "${element(libvirt_domain.node.*.network_interface.0.addresses.0, count.index)}"
    password = "${var.password}"
  }

  provisioner "file" {
    content     = "${element(data.template_file.role_grain.*.rendered, count.index)}"
    destination = "/etc/salt/grains"
  }
}

#####################
# Pillar values
#####################

resource "null_resource" "set_pillars" {
  # this will not be run at all when pillar==''
  count = "${signum(length(var.pillar))}"

  # this will fail if these TFs are not available
  depends_on = ["null_resource.copy_resources_admin",
                "null_resource.copy_salt",
                "null_resource.copy_manifests",
                "null_resource.set_role_grain"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl pillar set ${var.pillar}",
    ]
  }
}

##########################
# autorun
##########################

resource "null_resource" "autorun_admin" {
  # do it after copying Salt: otherwise we cannot tweak
  # the Salt stuff
  depends_on = ["null_resource.copy_resources_admin",
                "null_resource.copy_salt",
                "null_resource.copy_manifests",
                "null_resource.add_zypper_repo"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "for i in `ls -1 /tmp/caasp/autorun*.sh /tmp/caasp/autorun*/*.sh /tmp/caasp/admin/autorun*.sh /tmp/caasp/admin/autorun*/*.sh` ; do sh $i ; done",
    ]
  }
}

resource "null_resource" "autorun_nodes" {
  count      = "${var.nodes_count}"
  depends_on = ["null_resource.copy_resources_nodes"]
  connection {
    host     = "${element(libvirt_domain.node.*.network_interface.0.addresses.0, count.index)}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "for i in `ls -1 /tmp/caasp/autorun*.sh /tmp/caasp/autorun*/*.sh /tmp/caasp/nodes/autorun*.sh /tmp/caasp/nodes/autorun*/*.sh` ; do sh $i ; done",
    ]
  }
}

resource "null_resource" "autorun" {
  depends_on = ["null_resource.autorun_admin", "null_resource.autorun_nodes"]
}

##########################
# set the dashboard
##########################

resource "null_resource" "set_dashboard_host_admin" {
  depends_on = ["null_resource.copy_resources_admin"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl dns add dashboard 127.0.0.1",
    ]
  }
}

resource "null_resource" "set_dashboard_host_nodes" {
  count      = "${var.nodes_count}"
  depends_on = ["null_resource.copy_resources_nodes"]
  connection {
    host     = "${element(libvirt_domain.node.*.network_interface.0.addresses.0, count.index)}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl dns add dashboard ${libvirt_domain.admin.network_interface.0.addresses.0}",
    ]
  }
}

#####################
# Activation
#####################

# we must activate the admin node
resource "null_resource" "activate" {
  count      = "${var.activate ? 1 : 0}"
  depends_on = ["null_resource.copy_manifests",
                "null_resource.copy_salt",
                "null_resource.copy_resources_admin"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl activate",
    ]
  }
}

#####################
# Orchestration
#####################

resource "null_resource" "orchestrate" {
  count      = "${var.orchestrate ? 1 : 0}"
  depends_on = ["null_resource.copy_resources_admin",
                "null_resource.copy_manifests",
                "null_resource.copy_salt",
                "null_resource.autorun",
                "null_resource.set_role_grain",
                "null_resource.set_pillars"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  # before orchestrating, we must accept and wait for
  # nodes_count+2 (because of "ca" and "admin") keys to be accepted
  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl keys accept-wait ${var.nodes_count + 2}",
      "sh /tmp/caasp/caaspctl orchestrate",
    ]
  }
}

##########################
# Extra repo
##########################

resource "null_resource" "add_zypper_repo_admin" {
  count      = "${length(var.repo_url) == 0 ? 0 : 1}"
  depends_on = ["null_resource.copy_resources_admin"]
  connection {
    host     = "${libvirt_domain.admin.network_interface.0.addresses.0}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl zypper ar -n --no-gpg-checks -Gf ${var.repo_url} ${var.repo_name}",
    ]
  }
}

resource "null_resource" "add_zypper_repo_nodes" {
  count      = "${length(var.repo_url) == 0 ? 0 : var.nodes_count}"
  depends_on = ["null_resource.copy_resources_nodes"]
  connection {
    host     = "${element(libvirt_domain.node.*.network_interface.0.addresses.0, count.index)}"
    password = "${var.password}"
  }

  provisioner "remote-exec" {
    inline = [
      "sh /tmp/caasp/caaspctl zypper ar -n --no-gpg-checks -Gf ${var.repo_url} ${var.repo_name}",
    ]
  }
}

resource "null_resource" "add_zypper_repo" {
  depends_on = ["null_resource.add_zypper_repo_admin", "null_resource.add_zypper_repo_nodes"]
}

