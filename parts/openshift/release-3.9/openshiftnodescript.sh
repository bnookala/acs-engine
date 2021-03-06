#!/bin/bash -ex

# TODO: /etc/dnsmasq.d/origin-upstream-dns.conf is currently hardcoded; it
# probably shouldn't be
SERVICE_TYPE=origin
if [ -f "/etc/sysconfig/atomic-openshift-node" ]; then
    SERVICE_TYPE=atomic-openshift
fi

# TODO: with WALinuxAgent>=v2.2.21 (https://github.com/Azure/WALinuxAgent/pull/1005)
# we should be able to append context=system_u:object_r:container_var_lib_t:s0
# to ResourceDisk.MountOptions in /etc/waagent.conf and remove this stanza.
systemctl stop docker.service
restorecon -R /var/lib/docker
systemctl start docker.service

{{if eq .Role "infra"}}
echo "BOOTSTRAP_CONFIG_NAME=node-config-infra" >>/etc/sysconfig/${SERVICE_TYPE}-node
{{else}}
echo "BOOTSTRAP_CONFIG_NAME=node-config-compute" >>/etc/sysconfig/${SERVICE_TYPE}-node
{{end}}

sed -i -e "s#--loglevel=2#--loglevel=4#" /etc/sysconfig/${SERVICE_TYPE}-node

rm -rf /etc/etcd/* /etc/origin/master/* /etc/origin/node/*

( cd / && base64 -d <<< {{ .ConfigBundle }} | tar -xz)

cp /etc/origin/node/ca.crt /etc/pki/ca-trust/source/anchors/openshift-ca.crt
update-ca-trust

# note: ${SERVICE_TYPE}-node crash loops until master is up
systemctl enable ${SERVICE_TYPE}-node.service
systemctl start ${SERVICE_TYPE}-node.service &

while [[ $(KUBECONFIG=/etc/origin/node/node.kubeconfig oc get node $(hostname) -o template \
    --template '{{`{{range .status.conditions}}{{if eq .type "Ready"}}{{.status}}{{end}}{{end}}`}}') != True ]]; do
    sleep 1
done
