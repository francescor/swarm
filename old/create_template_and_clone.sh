# HOW to clone and provision an Ubuntu VM with cloud-init in Proxmox
#
# Adapted from https://gist.github.com/reluce/797515dc8b906eb07f54393a119df9a7
# See also https://pve.proxmox.com/wiki/Cloud-Init_Support

# All commands will be executed on a Proxmox host

# Innstall virt-customize
# apt update
# apt install libguestfs-tools

# Have the cloud-init snippet ready at something like
cat /var/lib/vz/snippets/cloud_init_ubuntu22_04_version00.yml

# Enable out traffic
iptables -I OUTPUT -j ACCEPT
# Get image
wget https://cloud-images.ubuntu.com/jammy/current/jammy-server-cloudimg-amd64.img
# Install qemu-guest-agent on the image. Additional packages can be specified by separating with a comma.
virt-customize -a jammy-server-cloudimg-amd64.img --install qemu-guest-agent
virt-customize -a jammy-server-cloudimg-amd64.img --update
# close proxmox output traffic
shorewall restart

# Next, we create a Proxmox VM template.
# Change values for your bridge and storage and change defaults to your liking.
qm create 9000 --name "ubuntu-template" --memory 2048 --cores 2 --net0 virtio,bridge=vmbr1 --scsihw virtio-scsi-pci
qm set 9000 --scsi0 local-zfs:0,import-from=/root/jammy-server-cloudimg-amd64.img
# Use cloud-init
qm set 9000 --ide2 local-zfs:cloudinit
qm set 9000 --boot order=scsi0
# we may skip this
qm set 9000 --serial0 socket --vga serial0
# key for cloudinit (user: ubuntu)
qm set 9000 --sshkey /root/id_ed25519.pub
qm set 9000 --agent enabled=1
# create a template (a read only disk used by linked clones)
qm template 9000
# create a linked clone
VM_ID=200
qm clone 9000 $VM_ID --name ubuntu-clone
qm set $VM_ID --ipconfig0 ip=10.10.10.${VM_ID}/24,gw=10.10.10.254
# take the latest version of cloud-init
CLOUD_INIT_SNIPPET=`ls -v /var/lib/vz/snippets/cloud_init_ubuntu22_04_version_*.yml | tail -n 1`
SNIPPET=VM_${VM_ID}_`basename ${CLOUD_INIT_SNIPPET}`
cp $CLOUD_INIT_SNIPPET  /var/lib/vz/snippets/${SNIPPET}
# customize hostname
sed -i "s/MY_HOSTNAME/ubuntu-${VM_ID}/g" /var/lib/vz/snippets/${SNIPPET}
qm set $VM_ID --cicustom "user=local:snippets/${SNIPPET}"
# Resize disk
qm resize $VM_ID scsi0 +20G
# Start VM
qm start $VM_ID

# Enter VM
ssh ubuntu@10.10.10.200
# follow cloud init output (it should reboot)
tail -f /var/log/cloud-init-output.log 

