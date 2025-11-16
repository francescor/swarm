# Docker swarm in Proxmox


The swarm will consist of a nodes created with cloud-init in Proxmox.

A special "NFS node" is setup with NFS share for all other nodes (to store mainly stack files and config), and also with an external SMB/CIFS (e.g. Hetzner's StorageBox) mounted to backup data.


# Requirement

Proxmox server version supporting cloud-init.

Enable `Snippets` in content for `local` storage

# Credentials

Create `secrets`

```
cat secrets
# Samba CIFS credentials
SMB_USERNAME=uuuuuuuuuu
SMB_PASSWORD=xxxx
# NFS credentials
NFS_SHARE_PASSWORD=xxxxxxxxx
```

Add your public SSH key in `ssh_public_keys/id_ed25519.pub`

# Setup the Storage node
In a Proxmox host, create one NFS server with

```
# IP will be: 10.10.10.210
su -
./create_nfs_server_vm.sh 210
```

# Wireguard for the swarm

An interesting setup is to route all outgoing traffic of the swarm by vpn/wireguard.

This can be accomplished by installing wireguard on the NFS node and set it as the gateway for all swarm nodes: a wireguard peers
to a VPN wireguard provider (mullvad).

```
# setup for NFS node
    - content: |
        # allow forwarding traffic for this VM to be a gateway
        # (it will be a wireguard connected to mullvad)
        net.ipv4.ip_forward=1
      path: /etc/sysctl.conf
      append: true
    - content: |
        # Get the following from mullvad (expire 13 Aug 2024)
        [Interface]
        # Device: Speedy Camel
        PrivateKey = xxxxxxxxx
        Address = x.x.x.x/32
        #  DNS = x.x.x.x
        ####################################################
        # iptables firewall rules                          #
        ####################################################
        #    We enable I/O traffic for the VPN virtual interface: wg0
        PostUp   = iptables -A FORWARD --in-interface  wg0 -j ACCEPT
        PostUp   = iptables -A FORWARD --out-interface wg0 -j ACCEPT
        # allow peers to surf the internet using mullvad
        PostUp   = iptables -t nat -A POSTROUTING --source 10.10.10.0/24 --out-interface mullvad -j MASQUERADE
        PostDown = iptables -t nat -D POSTROUTING --source 10.10.10.0/24 --out-interface mullvad -j MASQUERADE

        [Peer]
        PublicKey = xxxxxxxxxxxxxxxxxxxxxxxx
        AllowedIPs = 0.0.0.0/0
        Endpoint = x.x.x.x:3284
      path: /etc/wireguard/mullvad.conf

```

and setup for nodes

```
# we use the nfs server to reach the internet (it has mullvad)
I qm set $VM_ID --ipconfig0 ip=10.10.10.${IP}/24,gw=10.10.10.210
```

We've [removed this feature](https://github.com/francescor/swarm/commit/2c985b5290ee51733baed9aa7aa7cb97ffdad721).

# Swarm nodes

In a Proxmox host, create 3 swarm nodes with

```
./create_swarm_vm.sh 201 # leader
./create_swarm_vm.sh 202
./create_swarm_vm.sh 203
```

You can enter new nodes with a tunnel on proxmox

```
# add in .ssh/config
Host swarm-201.myswarm.local
  HostName 10.10.10.201
  ProxyCommand ssh myproxmox.example.com -W %h:%p
Host swarm-202.myswarm.local
  HostName 10.10.10.202
  ProxyCommand ssh myproxmox.example.com -W %h:%p
Host swarm-203.myswarm.local
  HostName 10.10.10.203
  ProxyCommand ssh myproxmox.example.com -W %h:%p
Host swarm-nfs.myswarm.local
  HostName 10.10.10.210
  ProxyCommand ssh myproxmox.example.com -W %h:%p
```

so now you can

```
# ubuntu is sudo with no password
ssh ubuntu@swarm-201.myswarm.local
```

# Swarm init


https://docs.docker.com/engine/reference/commandline/swarm_init/

```
# enter what will be the leader
ssh ubuntu@10.10.10.201
```
then start keepalived on leader (for simplicity we se the keepalive master to this leader,
but the master for keepalive could be any other node)

```
# execute keepalived, so to reach the swarm with 10.10.10.200
sudo /root/docker-run-keepalived-master.sh
```

now initialize the swarm

```
docker swarm init  --max-snapshots 2 \
                   --default-addr-pool 10.22.0.0/16 \
                   --default-addr-pool-mask-length 24 \
                   --advertise-addr 10.10.10.201
```

the get the command to add other nodes with

```
docker swarm join-token manager
```


Joint other nodes

```
ssh 10.10.10.202
sudo /root/docker-run-keepalived.sh

docker swarm join --token xxxxxxxxxxxxxxxxxxx 10.10.10.201:2377

ssh 10.10.10.203
sudo /root/docker-run-keepalived.sh

docker swarm join --token xxxxxxxxxxxxxxxxxxx 10.10.10.201:2377
```

# Set Proxmox boot order

In case of reboot of the Proxmox host, we want the NFS server to be up before the swarm nodes, so give
a `1` to NFS server as boot priority in Proxmox, and 9999201, 9999202, 9999203 to others


# Tips on how to plan a data path for your docker data

https://wiki.servarr.com/docker-guide#consistent-and-well-planned-paths
