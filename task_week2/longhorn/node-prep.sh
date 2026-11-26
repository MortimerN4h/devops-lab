#!/usr/bin/env bash
# Prepare ONE node (Ubuntu 24.04) for Longhorn. Run on EVERY node, as root. Safe to run again.
# From the bastion, without logging in:   ssh -i ~/.ssh/devops-rke2 ubuntu@<node IP> 'sudo bash -s' < node-prep.sh
set -euo pipefail

# 1) Packages
#    open-iscsi : Longhorn attaches each volume to the node as an iSCSI disk (/dev/sdX) -> needs the iSCSI initiator
#    nfs-common : NFS client, for ReadWriteMany volumes (several pods share one volume) and NFS backups
#    cryptsetup : encrypted volumes (optional feature, the preflight check asks for it)
apt-get update -q
DEBIAN_FRONTEND=noninteractive apt-get install -y -q open-iscsi nfs-common cryptsetup

# 2) iscsid = the iSCSI daemon. enable = start at every boot, --now = start now
systemctl enable --now iscsid

# 3) Kernel modules: load now + at every boot (files in /etc/modules-load.d/ are read at boot)
modprobe iscsi_tcp
modprobe dm_crypt
printf 'iscsi_tcp\ndm_crypt\n' > /etc/modules-load.d/longhorn.conf

# 4) multipathd (enabled on Ubuntu) grabs every new /dev/sdX disk it sees, including Longhorn's iSCSI disks,
#    and then the pod cannot mount its volume ("already mounted or mount point busy").
#    EC2 disks are /dev/nvme*, so telling multipathd to ignore all sd* disks is safe here.
if systemctl is-enabled --quiet multipathd 2>/dev/null; then
  if ! grep -q 'devnode "\^sd\[a-z0-9\]+"' /etc/multipath.conf 2>/dev/null; then
    cat >> /etc/multipath.conf <<'EOF'
blacklist {
    devnode "^sd[a-z0-9]+"
}
EOF
  fi
  systemctl restart multipathd
fi

echo "$(hostname): iscsid $(systemctl is-active iscsid), modules: $(lsmod | grep -oE '^(iscsi_tcp|dm_crypt)' | tr '\n' ' ')"
