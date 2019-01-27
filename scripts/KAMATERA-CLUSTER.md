# Create a Kamatera cluster

Step-by-step guide to create a production-grade cluster using Kamatera servers

## Prerequisites

Make sure you have all the required prerequisites before starting:

* Kamatera API credentials which you can get from the [Kamatera console](https://console.kamatera.com/keys) under `API` > `Keys`.
* Linux compatible PC with the following:
  * Standard Linux apps like Bash, Curl
  * Docker and Docker Machine: https://docs.docker.com/machine/install-machine/
  * jq: https://stedolan.github.io/jq/
* Access to set DNS A records for Rancher and Jenkins (e.g. rancher.your-domain.com / jenkins.your-domain.com)
* Email address to use for Let's Encrypt registration

## Create an internal VLAN network

* From the Kamatera console web-ui:
    * My Cloud > Networks > Create New Network:
        * VLAN Name: my-cluster
        * IP Address Scope: 172.16.0.0 / 23
        * Create Network
    * My Cloud > Servers
        * Edit each server and assign to the VLAN with an internal IP

## Create and setup the cluster management machine

Install the `docker-machine-server.sh` script:

```
curl -s -L https://raw.githubusercontent.com/OriHoch/docker-machine-server/v0.0.3/docker-machine-server.sh \
    | sudo tee /usr/local/bin/docker-machine-server.sh >/dev/null &&\
sudo chmod +x /usr/local/bin/docker-machine-server.sh
```

Install the `kamatera-cluster.sh` script:

```
curl -s -L https://raw.githubusercontent.com/OriHoch/docker-machine-server/v0.0.3/scripts/kamatera-cluster.sh \
    | sudo tee /usr/local/bin/kamatera-cluster.sh >/dev/null &&\
sudo chmod +x /usr/local/bin/kamatera-cluster.sh
```

Run the interactive management server creation script:

```
kamatera-cluster.sh "0.0.3" "your-private-network-name"
```

## Deploy an NFS server for cluster storage

You can deploy the NFS server to the management machine or a dedicated machine

ssh to the storage machine:

```
docker-machine ssh my-machine
```

Run the following from the SSH shell of the relevant machine to setup NFS:

```
apt install -y nfs-kernel-server &&\
mkdir -p /srv/default && echo "Hello from Kamatera!" > /srv/default/hello.txt &&\
chown -R nobody:nogroup /srv/default/ && chmod 777 /srv/default/ &&\
echo '/srv/default *(rw,sync,no_subtree_check)' > /etc/exports &&\
exportfs -a &&\
systemctl restart nfs-kernel-server
```

Get the server's private IP from the Kamatera Console

To use this NFS share, use the private IP from any machine on the same network.

NFS mount path should be a subpath under /srv/default/

## Create a Kubernetes cluster using Rancher

Access the Rancher web-UI at your domain and run the first time setup

Set the default Docker for nodes to the supported version

* Global > Settings > engine-install-url > edit
    * Value: `https://releases.rancher.com/install-docker/18.09.1.sh`
    * Save

Add the Kamatera Docker Machine driver

* Node Drivers > Add Node Driver >
    * Downlad URL: `https://github.com/OriHoch/docker-machine-driver-kamatera/releases/download/v1.0.0-RC1/docker-machine-driver-kamatera_v1.0.0-RC1_linux_amd64.tar.gz`
    * Create
* Node Drivers > Wait for Kamatera driver to be active

Create the first cluster node

* Clusters > Add cluster >
    * From nodes in an infrastructure provider: Kamatera
    * Cluster name: `my-cluster`
    * main node pool
        * Name Prefix: `my-cluster-pool`
        * Count: 1
        * Template: create new template:
            * apiClientId / apiSecret: set your Kamatera credentials
            * Set options according to your requirements, see [Kamatera server options](https://console.kamatera.com/service/server) for the available options (must be logged-in to Kamatera console)
            * CPU must be at least: `2B`
            * RAM must be at least: `2048`
            * Disk size must be at least: `30`
            * Private Network Name: your-private-network-name
            * Name: `kamatera-node`
            * Engine options > Storage Driver: `overlay2`
            * Create template
        * set checkboxex: etcd, Control Plane, Worker
    * Create cluster
* Wait for cluster to be provisioned

After the first node was provisioned, you can add additional nodes:

* Cluster > Nodes > click on the plus sign to add nodes, to ensure private IP allocation, add 1 node at a time

## Install a storage class

A storage class allows deployments to use the NFS server from any workload

Deploy the nfs-client-provisioner:

* Global > Catalogs > Enable Helm Stable catalog
* Default > Catalog Apps > Launch nfs-client-provisioner chart:
    * Set the following values:
        * `nfs.server=x.x.x.x`
        * `nfs.path=/srv/default`

## Install private Docker registry

Deploy docker-registry to provide private registry services to the cluster

Create an htpasswd user/password for the private registry authentication:

Run the following from your local PC (replace USERNAME / PASSWORD):

```
docker run --entrypoint htpasswd registry:2 -Bbn USERNAME PASSWORD
```

Copy the last output line and use as the secrets.htpasswd value

* Default > Catalog Apps >
    * Launch docker-registry (from Helm)
    * Set the following values to configure storage:
        * `secrets.htpasswd	= THE_HTPASSWD_SECRET_VALUE`
        * `persistence.enabled = true`
        * `persistence.size = 20Gi`
        * `persistence.storageClass = nfs-client`

Add the registry to Rancher

* Default > Resources > Registries > Add Registry:
    * Name: `my-registry`
    * Available to all namespaces in project
    * Address: custom - `docker-registry.docker-registry` - REGISTRY_USERNAME - REGISTRY_PASSWORD
    * Save

## Deploy test workloads

* Rancher > your-cluster > default >
    * Workloads > Deploy >
        * Name: `postgres`
        * Scalable deployment of `3` pods
        * Docker image: `postgres`
        * Namespace: `test`
        * Add port: 5432 - TCP - Cluster IP - Same as container port
        * Environment variables > Add variable > `POSTGRES_PASSWORD` = `123456`
        * Launch
    * Workloads > Deploy >
        * Name: `ubuntu`
        * Scalable deployment of `1` pods
        * Docker image: `ubuntu`
        * Namespace: `test`
        * Launch

Verify the deployments -

Execute a shell on the Ubuntu deployment

* your-cluster > default >
    * Workloads > ubuntu > Execute shell:

From the ubuntu shell, install postgresql:

```
apt-get update && apt-get install -y postgresql-client
```

Start a postgres database shell:

```
PGPASSWORD=123456 psql -h postgres -U postgres -d postgres
```

From the database shell, create a database table and insert a row:

```
CREATE TABLE foo (bar varchar(40) NOT NULL);
INSERT INTO foo values ('Hello Kubernetes!');
```

Type `\q` to exit the database shell

From the Ubuntu shell, run the following script to reconnect to the DB and get the values from the table you created:

```
PGPASSWORD=123456 psql -h postgres -U postgres -d postgres -c "select * from foo;"
```

Try to run it a few times, you'll notice it sometimes returns an error.

This error is because the `postgres` service is backed by 3 pods, each pod serving an independent database

Close the Rancher ubuntu shell

* Rancher web-ui > your cluster > Default >
    * Workloads > Service Discovery >
        * Click on the `postgres` service under the `test` namespace
        * This is a default service created by Rancher with the same name as the created workload
        * You can see it resolves to the `postgres` workload
    * Workloads > Workloads >
        * Click on the `postgres` workload under the `test` namespace
        * You can see this workload is served by 3 pods
        * The pods don't share any volumes, so each DB is independent

### Add a sidecar to the postgres workload

To make sure all DBs have the same table and row on startup we could use a sidecar

The sidecar runs alongside each pod and can be used to do initialization, management or health checks

First, we'll create a configmap which contains the script the sidecar will run

* Rancher web-ui > your cluster > Default >
    * Resources > Config Maps > Add config map >
        * Name: `postgres-sidecar`
        * Namespace: `test`
        * Key: `entrypoint.sh`
        * Value:

```
set -e

echo Installing postgresql client

apt-get update && apt-get install -y postgresql-client

echo creating the table and inserting a row
echo DB connection is done to localhost as the sidecar shares networking with the postgres container in the same pod
echo retries with sleep intervals of 1 second until completes successfully
while sleep 1; do
    PGPASSWORD=123456 psql -h 127.0.0.1 -U postgres -d postgres -v ON_ERROR_STOP=1 -c "
        CREATE TABLE IF NOT EXISTS foo (bar varchar(40) NOT NULL);
        INSERT INTO foo values ('Hello Kubernetes!');
    " && break
done

echo completed successfully
echo keeping the sidecar running forever

while true; do sleep 86400; done
```

Save the configmap

Add the sidecar to the postgres workload:

* Rancher web-ui > your cluster > Default >
    * Workloads > Workloads >
        * Click on the `postgres` workload under the `test` namespace
            * Open the actions menu and click on "Add a sidecar":
                * Name: `sidecar`
                * Sidecar type: `Standard Container`
                * Docker image: `ubuntu`
                * Volumes > Add Volume > use a config map
                    * Config Map: `postgres-sidecar`
                    * Mount point: `/sidecar-configmap`
                * Show advanced options >
                    * Command > Command: `/bin/bash /sidecar-configmap/entrypoint.sh`
            * Create the sidecar
        * Click on the `postgres` workload under the `test` namespace
            * Open on the actions menu for one of the pods in the workload
            * Click on `view logs`
            * Switch to the `sidecar` container from the select-box above the logs
            * Follow the logs until it outputs `completed successfully`

Verify by executing a shell on the Ubuntu workload:

* Rancher web-ui > your cluster > Default >
    * Workloads > Workloads >
        * Open the actions menu for the ubuntu workload and click Execute Shell

Run the following in the Ubuntu shell:

```
apt-get update && apt-get install -y postgresql-client
PGPASSWORD=123456 psql -h postgres -U postgres -d postgres -c "select * from foo;"
```

Rerun the last command a few times to make sure it returns successfully each time

### Create a web-app

This DB doesn't do anything useful without a web-app

Let's create a simple web-app

Create a private GitHub repository with the following files:

**app.py**

```
import json
import psycopg2
from flask import Flask, jsonify

app = Flask(__name__)

@app.route("/")
def hello():
    conn = psycopg2.connect("dbname=postgres user=postgres host=postgres password=123456")
    cur = conn.cursor()
    cur.execute("SELECT * FROM foo;")
    res = jsonify(cur.fetchall())
    cur.close()
    conn.close()
    return res
```

**entrypoint.sh**

```
cd /usr/src
export FLASK_APP=app.py
exec python2.7 -m flask run -h 0.0.0.0
```

**Dockerfile**

```
FROM ubuntu
RUN apt-get update && apt-get install -y python-flask python-psycopg2
COPY app.py entrypoint.sh /usr/src/
ENTRYPOINT ["bash", "/usr/src/entrypoint.sh"]
```

**.rancher-pipeline.yml**

```
stages:
- name: build and publish
  steps:
  - publishImageConfig:
      dockerfilePath: ./Dockerfile
      buildContext: .
      tag: test-web-app
      pushRemote: true
      registry: docker-registry.docker-registry
timeout: 240
```

Setup Rancher pipelines to build your Docker image

* Rancher web-ui > your cluster > Default > Resources > Pipelines >
    * Follow the instructions to connect your private GitHub repository
    * Enable pipelines for the test-web-app repository
    * Trigger the test-web-app pipeline
    * On first pipeline run it may take a few minutes for Rancher to install Jenkins
    * If a job fails, try to Rerun it

Deploy the web-app workload using the published image

* Deploy a new workload in namespace `test`:
    * Name: web-app
    * Scalable deployment of `3` pods
    * Docker Image: `test-web-app`
    * Namespace: `test`
    * Add Port: 5000 - TCP - Cluster IP - Same as container port
    * Health check:
        * HTTP request returns a successful status
        * Request Path: `/`
        * Target container port: `5000`
    * Launch

Add an ingress to expose the web-app

* Create an Ingress to expose the web-app:
    * Workloads > Load Balancing > Add Ingress:
        * Name: `web-app`
        * Namespace: `test`
        * Specify a hostname to use: `test-web-app.your-domain.com`
        * Path: /
        * Target: `web-app`
        * Port: 5000
        * Save

The web-app is available on any worker node's IP in the cluster

Get a node's IP from cluster > nodes

Test with curl that it works:

```
curl -H "Host: test-web-app.your-domain.com" http://your.node.ip.address/
```

You can now set a DNS A record to that IP and set an SSL certificate by editing the web-app Ingress

## Next Steps

* [Kubernetes documentation](https://kubernetes.io/docs/home/)
* [Rancher documentation](https://rancher.com/docs/rancher/v2.x/en/overview/)