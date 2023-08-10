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
In a Proxmox host, create 3 swarm nodes with

```
./create_nfs_server_vm.sh 210
```

# Swarm nodes
In a Proxmox host, create 3 swarm nodes with

```
./create_swarm_vm.sh 201 # master
./create_swarm_vm.sh 202
./create_swarm_vm.sh 203
```

# Swarm init


https://docs.docker.com/engine/reference/commandline/swarm_init/

```
# enter what will be the leader
ssh ubuntu@10.10.10.201
# initialize swarm
docker swarm init  --max-snapshots 2 \
                   --default-addr-pool 10.22.0.0/16 \
                   --default-addr-pool-mask-length 24

# get command to add other nodes
docker swarm join-token manager
```

then start keepalived on leader (for simplicity we se the keepalive master to this leader,
but the master for keepalive could be any other node)

```
# execute keepalived, so to reach the swarm with 10.10.10.200
sudo /root/docker-run-keepalived-master.sh
```

Joint other nodes

```
ssh 10.10.10.202
docker swarm join --token xxxxxxxxxxxxxxxxxxx 10.10.10.201:2377
sudo /root/docker-run-keepalived.sh

ssh 10.10.10.203
docker swarm join --token xxxxxxxxxxxxxxxxxxx 10.10.10.201:2377
sudo /root/docker-run-keepalived.sh
```
