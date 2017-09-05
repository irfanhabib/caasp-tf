#!/bin/bash

# Usage: ./deploy-ceph.sh MY_PUBLIC_IP

MY_IP=$@

kubectl create namespace ceph

# Deploy All in one Ceph
docker run -d --net=host -v /etc/ceph:/etc/ceph -e RGW_CIVETWEB_PORT=8088 -e MON_NAME=$MY_IP -e RGW_NAME=$MY_IP -e MON_IP=$MY_IP -e CEPH_PUBLIC_NETWORK=149.44.104.0/24 ceph/demo

# Write out ceph-client-admin-keyring-secret
sleep 60 
TMP=$(mktemp -d)
sudo cp -r /etc/ceph/* $TMP/
sudo chown -R 1000:1000 $TMP/

kubectl create secret generic ceph-secrets --from-file=$TMP/ceph.client.admin.keyring \
    --from-file=$TMP/ceph.conf \
    --from-file=$TMP/ceph.mon.keyring \
    --from-file=$TMP/monmap-ceph \
    --namespace=ceph

# Deploy RDB provisioner
kubectl apply -f deploy-rdb-provisioner.yaml --namespace=ceph

# Provision storage class
CEPH_CLIENT_ADMIN=$(cat $TMP/ceph.client.admin.keyring | grep key | cut -d' ' -f3)
kubectl create secret generic ceph-secret-admin --from-literal=ceph-client-key=$CEPH_CLIENT_ADMIN --namespace=ceph --type=kubernetes.io/rbd

STORAGE_CLASS=$(mktemp)

cat << EOF > $STORAGE_CLASS
apiVersion: storage.k8s.io/v1beta1
kind: StorageClass
metadata:
   name: slow
provisioner: ceph.com/rbd
parameters:
    monitors: $MY_IP:6789
    adminId: admin
    adminSecretName: ceph-secret-admin
    adminSecretNamespace: "ceph"
EOF

kubectl create -f $STORAGE_CLASS --namespace=ceph


