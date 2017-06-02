#
# Author(s): Alvaro Saurin <alvaro.saurin@suse.com>
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

# Makefile FOR DEVELOPERS
# if you are not a developer, just do "terraform apply"
#
# Usage:
# * install "sshpass", "wget"...
# * customize some of these vars (for example, putting them in a Makefile.local)
# * do "make dev-apply" (or some othe target)
#

# Note: you can overwrite these vars from command line with something like:
# make dev-apply CHECKOUTS_DIR=~/dev

# prefix for all the resources'
PREFIX            = caasp

# pool used for images in libvirt
LIBVIRT_POOL_NAME = personal
LIBVIRT_POOL_DIR  = ~/.libvirt/images

# some dis
CHECKOUTS_DIR     = ~/Development/SUSE
SALT_DIR          = $(CHECKOUTS_DIR)/k8s-salt
SALT_VM_DIR       = /usr/share/salt/kubernetes
E2E_TESTS_RUNNER  = $(CHECKOUTS_DIR)/automation/k8s-e2e-tests/e2e-tests

#####################################################################

# the directory with resources that will be copied to the VMs
RESOURCES_DIR    = resources

VARS_STAGING_A   = profiles/devel/images-staging-a.tfvars
VARS_STAGING_B   = profiles/devel/images-staging-b.tfvars

# VMs we use
VMS_NODES        = node_0 node_1
VMS_ALL          = admin $(VMS_NODES)
VMS_NUM_MINIONS  = 2

CAASPCTL         = /tmp/caasp/caaspctl
RUN_CAASPCTL     = bash $(CAASPCTL)

# environment variables we always pass to Terraform
TERRAFORM_VARS   = TF_VAR_prefix=$(PREFIX) \
	               TF_VAR_img_pool=$(LIBVIRT_POOL_NAME) \
	               TF_VAR_salt_dir=$(SALT_DIR)

# common options for ssh, rsync, etc
SSH              = sshpass -p "linux" ssh
SCP              = sshpass -p "linux" scp
SSH_OPTS         = -oStrictHostKeyChecking=no \
                   -oUserKnownHostsFile=/dev/null
EXCLUDE_ARGS     = --exclude='*.tfstate*' \
                   --exclude='.git*' \
                   --exclude='Makefile' \
                   --exclude='README.md' \
                   --exclude='*.sublime-*' \
                   --exclude='.idea' \
                   --exclude='*.tgz'
RSYNC_OPTS       = $(EXCLUDE_ARGS) -e '$(SSH) $(SSH_OPTS)' --delete

# stuff for building distributions
DIST_CONT        = *.profile  k8s-setup terraform
DIST_TAR         = kubernetes-terraform.tgz
TAR_ARGS         = $(EXCLUDE_ARGS) -zcvf

# a kubeconfig we will download from the master
KUBECONFIG       = kubeconfig

# files to remove after a "destroy"
CLEANUP_FILES    = terraform.tfstate* \
                   admin.{tar,crt,key} ca.crt \
                   $(KUBECONFIG) \
		           $(LIBVIRT_POOL_DIR)/$(PREFIX)_*

# the dashboard and node IPs (might need a "terraform refresh" after a while)
ADMIN_IP         = `support/mk/get-admin-ip.sh`
NODES_IPS        = `support/mk/get-node-ip.sh`

# you can customimze vars in a local Makefile
-include Makefile.local

####################################################################
# CAASP
####################################################################

all:
	@echo "Makefile FOR DEVELOPERS"
	@echo "For regular users please do: terraform apply"

dev-apply-with-args:
	@echo ">>> Applying Terraform..."
	@env $(TERRAFORM_VARS) terraform apply $(ARGS)
	@sleep 10 && make dev-snapshot

dev-apply:
	make dev-apply-with-args
dev-apply-staging-a:
	make dev-apply-with-args ARGS="-var-file=$(VARS_STAGING_A) $(ARGS)"
dev-apply-staging-b:
	make dev-apply-with-args ARGS="-var-file=$(VARS_STAGING_B) $(ARGS)"

dev-destroy:
	-@for h in $(VMS_ALL) ; do \
		echo ">>> Destroying snapshots for $(PREFIX)_$$h" ; \
		while sudo virsh snapshot-delete $(PREFIX)_$$h --current &>/dev/null ; do echo ; done ; \
	done
	-terraform destroy -force
	-rm -f $(CLEANUP_FILES)
	-@notify-send "k8s: cluster destruction finished" &>/dev/null

dev-copy:
	@echo ">>> Copying the VM's resources to /tmp/caasp"
	@rsync -avz $(RSYNC_OPTS) $(RESOURCES_DIR)/common/ root@$(ADMIN_IP):/tmp/caasp/
	@rsync -avz $(RSYNC_OPTS) $(RESOURCES_DIR)/admin/  root@$(ADMIN_IP):/tmp/caasp/admin/
	@echo ">>> Making fs RW-able"
	@make dev-ssh CMD='$(RUN_CAASPCTL) rw on'
	@echo ">>> Copying the Salt scripts/pillar"
	@rsync -avz $(RSYNC_OPTS) $(SALT_DIR)/  root@$(ADMIN_IP):$(SALT_VM_DIR)/
	@echo ">>> Synchronizing Salt stuff"
	@make dev-ssh CMD='$(RUN_CAASPCTL) salt sync'

dev-orch: dev-copy
	@make dev-ssh CMD='$(RUN_CAASPCTL) orchestrate'
	@rm -f $(KUBECONFIG)
	-@notify-send "k8s: cluster orchestration finished" &>/dev/null

dev-reorch: dev-rollback _wait-20s dev-orch
dev:        dev-apply dev-orch

dev-restart-master: dev-copy
	@make dev-ssh CMD='$(RUN_CAASPCTL) salt restart-master'
dev-restart-api: dev-copy
	@make dev-ssh CMD='$(RUN_CAASPCTL) salt restart-api'

# some times we might need to refresh data
# and readjust some stuff (ie, when IPs change)
dev-refresh:
	support/mk/refresh-vms.sh

dev-kubeconfig: $(KUBECONFIG)
$(KUBECONFIG):
	@echo ">>> Generating a kubeconfig"
	@make dev-ssh CMD='$(RUN_CAASPCTL) kubeconfig gen'
	@echo ">>> Getting the kubeconfig"
	@$(SCP) -q $(SSH_OPTS) root@$(ADMIN_IP):.kube/config $(KUBECONFIG)
	@echo ">>> done."

# run the e2e tests
dev-e2e: $(KUBECONFIG)
	@echo ">>> Running the kubernetes e2e tests"
	$(E2E_TESTS_RUNNER) --kubeconfig $(KUBECONFIG) $(E2E_ARGS)
	-@notify-send "k8s: e2e tests finished" &>/dev/null

####################################################################
# profiles

dev-profile-apply: dev-profile-clean
	@echo ">>> Applying development profile"
	@for i in profiles/devel/profile-devel*.tf ; do ln -sf $$i ; done

dev-profile-clean:
	@echo ">>> Cleaning profile files"
	@for i in *.tf ; do \
		if [ -L $$i ] ; then \
			l=`readlink $$i` ; \
			[[ $$l == profiles/* ]] && rm -f $$i ; \
		fi ; \
	done

####################################################################
# updates & reboots

dev-nodes-dist-update:
	@make dev-ssh-nodes CMD='$(RUN_CAASPCTL) zypper update'
	-@notify-send "k8s: cluster updates downloaded... would need a reboot" &>/dev/null

dev-nodes-reboot:
	@make dev-ssh-nodes CMD='$(RUN_CAASPCTL) reboot'
	-@notify-send "k8s: nodes rebooted" &>/dev/null

####################################################################
# some ssh convencience targets

dev-ssh: dev-ssh-admin
dev-ssh-admin:
	@$(SSH) -q $(SSH_OPTS) root@$(ADMIN_IP) '$(CMD)'

dev-ssh-nodes:
	@for node in $(NODES_IPS) ; do \
		$(SSH) -q $(SSH_OPTS) root@$$node '$(CMD)' ; \
	done

dev-ssh-node-0:
	@$(SSH) $(SSH_OPTS) root@`support/mk/get-node-ip.sh 0` '$(CMD)'
dev-ssh-node-1:
	@$(SSH) $(SSH_OPTS) root@`support/mk/get-node-ip.sh 1` '$(CMD)'

dev-ssh-salt-master:
	@make dev-ssh CMD='$(RUN_CAASPCTL) salt $(CMD)'

####################################################################
# some logging utilities
dev-logs-salt-master:
	@echo ">>> Dumping logs from the Salt master"
	@make dev-ssh CMD='$(RUN_CAASPCTL) salt logs'

dev-logs-events:
	@echo ">>> Dumping Salt events at the master"
	@make dev-ssh CMD='$(RUN_CAASPCTL) salt events'

####################################################################
# VMs management

dev-snapshot:
	@echo ">>> Creating snapshots..."
	@for h in $(VMS_ALL) ; do \
		sudo virsh snapshot-create --atomic $(PREFIX)_$$h ; \
	done
	-@notify-send "k8s: cluster creation finished" &>/dev/null

dev-suspend:
	@echo ">>> Suspending VMs before rolling back"
	-@for h in $(VMS_ALL) ; do \
		sudo virsh suspend $(PREFIX)_$$h ; \
	done
	-@notify-send "k8s: all VMs suspended" &>/dev/null

dev-resume:
	@echo ">>> Resuming VMs before rolling back"
	-@for h in $(VMS_ALL) ; do \
		sudo virsh resume $(PREFIX)_$$h ; \
	done
	-@notify-send "k8s: all VMs suspended" &>/dev/null

# NOTE: we need to "echo 1 > /proc/sys/vm/overcommit_memory"
#       or qemu-kvm will kill our machine...
dev-rollback: dev-suspend
	@for h in $(VMS_ALL) ; do \
		echo ">>> Rolling back $(PREFIX)_$$h" ; \
		sudo virsh snapshot-revert --current --running $(PREFIX)_$$h ; \
	done
	@echo ">>> Refreshing Terraform data"
	-@make dev-refresh
	-@notify-send "k8s: all VMs rolled back" &>/dev/null

####################################################################
# packages installation

_install-rpms-on:
	@echo "Copying RPMs to $(NODE)"
	@$(SSH) -q $(SSH_OPTS) root@$(NODE) 'rm -rf /tmp/rpms && mkdir -p /tmp/rpms'
	@$(SCP) -q $(SSH_OPTS) rpms/* root@$(NODE):/tmp/rpms/
	@$(SSH) -q $(SSH_OPTS) root@$(NODE) 'ls -lisah /tmp/rpms/*'
	@echo "Importing keys"
	@$(SSH) -q $(SSH_OPTS) root@$(NODE) 'caaspctl rw 1'
	@$(SSH) -q $(SSH_OPTS) root@$(NODE) 'rpm --import /tmp/rpms/*.key /tmp/rpms/*.pub || /bin/true'
	@echo "Installing packages"
	@$(SSH) -q $(SSH_OPTS) root@$(NODE) 'caaspctl zypper in -y /tmp/rpms/*.rpm'
	@echo "Rebooting $(NODE)"
	@-$(SSH) -q $(SSH_OPTS) root@$(NODE) 'reboot'
	-@notify-send "k8s: packages installed in $(NODE)" &>/dev/null

dev-install-rpms-nodes:
	@for node in $(NODES_IPS) ; do \
		make _install-rpms-on NODE=$$node ; \
	done

####################################################################
# aux

.PHONY: _wait-20s
_wait-20s:
	@echo ">>> Waiting some time..."
	@sleep 20

####################################################################
# distribution

dist:
	@echo "Creating distribution package"
	tar $(TAR_ARGS) $(DIST_TAR) $(DIST_CONT)
