#!/bin/bash

# Create a Proxmox VM with latest ubuntu & cloud_init
# be executed on a Proxmox host
# See also https://pve.proxmox.com/wiki/Cloud-Init_Support

# The snippets dir in Proxmox
SNIPPETS_DIR=/var/lib/vz/snippets/
# ssh for root access
SSH_KEY=ssh_public_keys/id_ed25519.pub

# load secrets
source secrets

if [ $# -eq 0 ]
  then
    script_name=$(basename "$0")
    echo "Error: no arguments supplied"
    echo
    echo "Execute:"
    echo "$script_name 210"
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
if (( $1 < 210 || $1 > 215 )); then
  echo "Error: Number is not within the range of 210-215"
  exit 1
fi

# Have the cloud-init snippet ready at something like
# customize: here we choose VMid 210, 211...
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
qm create $VM_ID --name "nfs${IP}" --memory 2048 --cores 1 --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-pci
qm set $VM_ID --scsi0 local-zfs:0,import-from=/tmp/downloaded_image.img,backup=1
# add disk for NFS share
qm set $VM_ID --scsi1 local-zfs:200,backup=1
# Use cloud-init
qm set $VM_ID --ide2 local-zfs:cloudinit
qm set $VM_ID --boot order=scsi0
# we may skip this, but is useful to see the output of cloud-init in Proxmox console
qm set $VM_ID --serial0 socket --vga serial0
# key for cloudinit (user: ubuntu)
qm set $VM_ID --sshkey $SSH_KEY
qm set $VM_ID --agent enabled=1
qm set $VM_ID --ipconfig0 ip=10.10.10.${IP}/24,gw=10.10.10.254
# start VM at proxmox boot
qm set $VM_ID --onboot 1
# set startup: order=1
qm set $VM_ID --startup order=1
# take the latest version of cloud-init
LATEST_CLOUD_INIT=`ls -v cloud-init/cloud_init_nfs_server_version_*.yml | tail -n 1`
SNIPPET=`basename ${LATEST_CLOUD_INIT}`
# cp -f $LATEST_CLOUD_INIT $SNIPPETS_DIR/${SNIPPET}
# use path for cp to avoid using aliases
/usr/bin/cp $LATEST_CLOUD_INIT $SNIPPETS_DIR/${SNIPPET}

# customize hostname
sed -i "s/my_hostname/nfs-${VM_ID}/g" $SNIPPETS_DIR/${SNIPPET}
sed -i "s/my_domain/aaahoy.local/g" $SNIPPETS_DIR/${SNIPPET}
sed -i "s/SMB_USERNAME/${SMB_USERNAME}/g" $SNIPPETS_DIR/${SNIPPET}
sed -i "s/SMB_PASSWORD/${SMB_PASSWORD}/g" $SNIPPETS_DIR/${SNIPPET}
qm set $VM_ID --cicustom "user=local:snippets/${SNIPPET}"
# Resize disk
qm resize $VM_ID scsi0 +30G
# Start VM
qm start $VM_ID

# Enter VM
echo
echo "VM $VM_ID created and started, enter with"
echo "ssh ubuntu@10.10.10.${VM_ID}"
# follow cloud init output (it should reboot)
# tail -f /var/log/cloud-init-output.log

