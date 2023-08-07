# Create a Proxmox VM with latest ubuntu & cloud_init

# See also https://pve.proxmox.com/wiki/Cloud-Init_Support


# The snippets dir in Proxmox
SNIPPETS_DIR=/var/lib/vz/snippets/
# ssh for root access
SSH_KEY=ssh_public_keys/id_ed25519.pub

# All commands will be executed on a Proxmox host

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
# cat /var/lib/vz/snippets/cloud_init_ubuntu22_04_version00.yml

VM_ID=$1
# Enable out traffic from Proxmox
iptables -I OUTPUT -j ACCEPT
# Get image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img --output-document=/tmp/downloaded_image.img
# re-enable firewall rules
shorewall restart
qm create $VM_ID --name "ubuntu${VM_ID}" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-pci
qm set $VM_ID --scsi0 local-zfs:0,import-from=/tmp/downloaded_image.img
# Use cloud-init
qm set $VM_ID --ide2 local-zfs:cloudinit
qm set $VM_ID --boot order=scsi0
# we may skip this, but is useful to see the output of cloud-init in Proxmox console
qm set $VM_ID --serial0 socket --vga serial0
# key for cloudinit (user: ubuntu)
qm set $VM_ID --sshkey $SSH_KEY
qm set $VM_ID --agent enabled=1
qm set $VM_ID --ipconfig0 ip=10.10.10.${VM_ID}/24,gw=10.10.10.254
# take the latest version of cloud-init
LATEST_CLOUD_INIT=`ls -v cloud-init/cloud_init_ubuntu22_04_version_*.yml | tail -n 1`
SNIPPET=VM_${VM_ID}_`basename ${LATEST_CLOUD_INIT}`
cp $LATEST_CLOUD_INIT $SNIPPETS_DIR/${SNIPPET}
# customize hostname
sed -i "s/MY_HOSTNAME/ubuntu-${VM_ID}/g" $SNIPPETS_DIR/${SNIPPET}
qm set $VM_ID --cicustom "user=local:snippets/${SNIPPET}"
# Resize disk
qm resize $VM_ID scsi0 +200G
# Start VM
qm start $VM_ID

# Enter VM
echo
echo "VM $VM_ID created and started, enter with"
echo "ssh ubuntu@10.10.10.${VM_ID}"
# follow cloud init output (it should reboot)
# tail -f /var/log/cloud-init-output.log 

