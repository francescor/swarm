# swarm
Docker swarm receipts



# Swarm init


https://docs.docker.com/engine/reference/commandline/swarm_init/

```
docker swarm init  --max-snapshots 2 \
                   --force-new-cluster \
                   --default-addr-pool 10.22.0.0/16 \
                   --default-addr-pool-mask-length 24
```
