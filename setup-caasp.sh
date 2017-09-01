#!/bin/bash

# Install DNS
kubectl apply -f https://raw.githubusercontent.com/SUSE/caasp-services/b0cf20ca424c41fa8eaef6d84bc5b5147e6f8b70/contrib/addons/kubedns/dns.yaml

# SSH into kube-master and change

cat << EOT >> /etc/kubernetes/controller-manager
KUBE_CONTROLLER_MANAGER_ARGS="$KUBE_CONTROLLER_MANAGER_ARGS \
     --enable-hostpath-provisioner \
     "
EOT

kubectl apply -f storageclass.yaml
# Add dashboard
kubectl create -f https://git.io/kube-dashboard-no-rbac