#!/bin/bash

# Create a Proxmox VM with latest ubuntu & cloud_init
# be executed on a Proxmox host
# See also https://pve.proxmox.com/wiki/Cloud-Init_Support

# The snippets dir in Proxmox
SNIPPETS_DIR=/var/lib/vz/snippets/
# ssh for root access
SSH_KEY=ssh_public_keys/id_ed25519.pub
NFS_SERVER_IP=10.10.10.210

# load secrets
source secrets

if [ $# -eq 0 ]
  then
    script_name=$(basename "$0")
    echo "Error: no arguments supplied"
    echo
    echo "Execute:"
    echo "$script_name 200"
    exit 1
fi

# assure ID is between permitted IP
# see /etc/shorewall/rules
# Check if the first parameter is a number
if ! [[ $1 =~ ^[0-9]+$ ]]; then
  echo "Error: parameter is not a number"
  exit 1
fi

# Check if the number is within the desired range
if (( $1 < 200 || $1 > 209 )); then
  echo "Error: Number is not within the range of 200-209"
  exit 1
fi

# Have the cloud-init snippet ready at something like
# customize: here we choose VMid 200, 201...
IP=$1
VM_ID="${IP}"

# Assure VM is not already present
qm list  | awk '{print $1}' | grep " $VM_ID"
if [ $? -eq 0 ]
  then
    echo "Error: VM with ID $VM_ID is already present"
    echo
    exit 1
fi

# Enable out traffic from Proxmox
iptables -I OUTPUT -j ACCEPT
# Get image
wget --no-clobber --output-document=/tmp/downloaded_image.img https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
# re-enable firewall rules
shorewall restart
qm create $VM_ID --name "swarm${IP}" --memory 10240 --cores 2 --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-pci
qm set $VM_ID --scsi0 local-zfs:0,import-from=/tmp/downloaded_image.img,backup=0
# add disk for /var/lib/docker disk
qm set $VM_ID --scsi1 local-zfs:100,backup=0
# Use cloud-init
qm set $VM_ID --ide2 local-zfs:cloudinit
qm set $VM_ID --boot order=scsi0
# we may skip this, but is useful to see the output of cloud-init in Proxmox console
qm set $VM_ID --serial0 socket --vga serial0
# key for cloudinit (user: ubuntu)
qm set $VM_ID --sshkey $SSH_KEY
qm set $VM_ID --agent enabled=1
# we use the nfs server to reach the internet (it has mullvad)
qm set $VM_ID --ipconfig0 ip=10.10.10.${IP}/24,gw=10.10.10.210
# get this from mullvad wireguard
qm set $VM_ID --nameserver 10.64.0.1
# start VM at proxmox boot
qm set $VM_ID --onboot 1
# set startup: order=9999020X
qm set $VM_ID --startup order=99990${IP}
# take the latest version of cloud-init
LATEST_CLOUD_INIT=`ls -v cloud-init/cloud_init_ubuntu22_04_version_*.yml | tail -n 1`
TEMPLATE_FILENAME=`basename ${LATEST_CLOUD_INIT}`
SNIPPET_FILENAME=VM_${VM_ID}_${TEMPLATE_FILENAME}
SNIPPET=${SNIPPETS_DIR}/${SNIPPET_FILENAME}
# copy template in proxmox snippet dir
# use path for cp to avoid using aliases
/usr/bin/cp $LATEST_CLOUD_INIT $SNIPPET
# customize hostname
sed -i "s/my_hostname/swarm-${VM_ID}/g" $SNIPPET
sed -i "s/my_domain/aaahoy.local/g" $SNIPPET
sed -i "s/SMB_USERNAME/${SMB_USERNAME}/g" $SNIPPET
sed -i "s/SMB_PASSWORD/${SMB_PASSWORD}/g" $SNIPPET
sed -i "s/NFS_SERVER_IP/${NFS_SERVER_IP}/g" $SNIPPET
qm set $VM_ID --cicustom "user=local:snippets/${SNIPPET_FILENAME}"
# Resize disk
qm resize $VM_ID scsi0 +50G
# Start VM
qm start $VM_ID

# Enter VM
echo
echo "VM $VM_ID created and started, enter with"
echo "ssh ubuntu@10.10.10.${VM_ID}"
# follow cloud init output (it should reboot)
# tail -f /var/log/cloud-init-output.log

