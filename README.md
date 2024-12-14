# Docker swarm in Proxmox

Create `secrets`

```
cat secrets
# Samba CIFS credentials
SMB_USERNAME=uuuuuuuuuu
SMB_PASSWORD=xxxx
# NFS credentials
NFS_SHARE_PASSWORD=xxxxxxxxx
```

# Storage
In a Proxmox host, create one NFS server with

```
# IP will be: 10.10.10.210
./create_nfs_server_vm.sh 210
```

# Wireguard for the swarm

The NFS server is also the gateway for all swarm nodes: a wireguard peers
to a VPN wireguard provider (mullvad).

Firewall traffic to the internet for swarm nodes use the NFS/Wireguard gw

# Swarm nodes

In a Proxmox host, create 3 swarm nodes with

```
./create_swarm_vm.sh 201 # leader
./create_swarm_vm.sh 202
./create_swarm_vm.sh 203
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
