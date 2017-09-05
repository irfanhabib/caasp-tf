#!/bin/bash

CAASP_MASTER=$@
# Install DNS
kubectl apply -f https://raw.githubusercontent.com/SUSE/caasp-services/b0cf20ca424c41fa8eaef6d84bc5b5147e6f8b70/contrib/addons/kubedns/dns.yaml
# Add dashboard
kubectl create -f https://git.io/kube-dashboard-no-rbac
# Install Helm
helm init

# SSH into kube-master and change

ssh root@$CAASP_MASTER 'cat << EOT > /etc/kubernetes/controller-manager
###
# The following values are used to configure the kubernetes controller-manager

# defaults from config and apiserver should be adequate

# Add your own!
KUBE_CONTROLLER_MANAGER_ARGS="\
    --leader-elect=true \
    --cluster-name=kubernetes \
    --enable-hostpath-provisioner \
    --cluster-cidr=172.20.0.0/16 \
    --service-account-private-key-file=/etc/pki/minion.key \
    --root-ca-file=/etc/pki/trust/anchors/SUSE_CaaSP_CA.crt \
"
EOT'

ssh root@$CAASP_MASTER 'sudo systemctl restart kube-controller-manager'

# Add Hostpath storage class
kubectl apply -f storageclass.yaml
