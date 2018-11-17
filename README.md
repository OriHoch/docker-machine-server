# Docker Machine Server

Scripts and documentation for rapid deployment and management of servers running on Docker Machines.

## Installation

[Install Docker Machine](https://docs.docker.com/machine/install-machine/)

## Create a machine

Create a cloud account for one of the [supported drivers](https://docs.docker.com/machine/drivers/) or [3rd party drivers](https://github.com/docker/docker.github.io/blob/master/machine/AVAILABLE_DRIVER_PLUGINS.md).

Follow the relevant driver documentation to create a machine with Ubuntu (known to work with 16.04 and 18.04).

Copy the docker-machine-server scripts to the machine:

```
DOCKER_MACHINE_SERVER_VERSION=0.0.1

docker-machine ssh $(docker-machine active) \
    'sudo bash -c "TEMPDIR=`mktemp -d` && cd \$TEMPDIR &&\
     wget -q https://github.com/OriHoch/docker-machine-server/archive/v'${DOCKER_MACHINE_SERVER_VERSION}'.tar.gz &&\
     tar -xzf 'v${DOCKER_MACHINE_SERVER_VERSION}'.tar.gz &&\
     rm -rf /usr/local/src/docker-machine-server && mkdir -p /usr/local/src/docker-machine-server &&\
     cp -rf docker-machine-server-'${DOCKER_MACHINE_SERVER_VERSION}'/* /usr/local/src/docker-machine-server/ &&\
     chmod +x /usr/local/src/docker-machine-server/ubuntu/*.sh &&\
     echo Great Success"'
```

## Deploy an app and expose via SSL

Set the target machine as the active Docker Machine

```

export TARGET_DOCKER_MACHINE_NAME=your-docker-machine

eval $(docker-machine env ${TARGET_DOCKER_MACHINE_NAME}) &&\
docker-machine active
```

Install and configure Nginx and Let's Encrypt (will delete existing configurations)

```
docker-machine ssh $(docker-machine active) \
    sudo /usr/local/src/docker-machine-server/ubuntu/install_nginx_ssl.sh
```

Get the server's IP:

```
docker-machine ip $(docker-machine active)
```

Register a subdomain to point to that IP

Register the SSL certificate, you may run this multiple times to add additional sub-domains

```
export LETSENCRYPT_EMAIL=your@email.com
export CERTBOT_DOMAINS="subdomain1.your-domain.com,subdomain2.your-domain.com"

# this should be the first one of the CERTBOT_DOMAINS
export LETSENCRYPT_DOMAIN=subdomain1.your-domain.com

docker-machine ssh $(docker-machine active) \
    sudo /usr/local/src/docker-machine-server/ubuntu/setup_ssl.sh ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAIN}
```

If you are adding domains to existing certificate, restart nginx: `docker-machine ssh $(docker-machine active) sudo systemctl restart nginx`

Deploy your app

The docker-machine-server code includes an example web-app for testing

Build and run the example web-app

```
docker-machine ssh $(docker-machine active) \
    sudo docker build -t flask-hello-world /usr/local/src/docker-machine-server/flask-hello-world &&\
( docker-machine ssh $(docker-machine active) sudo docker rm -f flask-hello-world || true ) &&\
docker-machine ssh $(docker-machine active) \
    sudo docker run -d --name flask-hello-world -p 5000:5000 flask-hello-world --host 0.0.0.0
```

Verify that the app is running:

```
docker-machine ssh $(docker-machine active) curl -s localhost:5000
```

Create the nginx configuration on the server at `/etc/nginx/snippets/flask-hello-world`

This example creates an http/2 compatible reverse proxy to the flask-hello-world at port 5000:

```
echo 'location / {
    proxy_pass http://localhost:5000;
    include snippets/http2_proxy.conf;
}' | docker-machine ssh $(docker-machine active) sudo tee /etc/nginx/snippets/flask-hello-world.conf
```

Add the flask-hello-world app to Nginx

```
export SERVER_NAME=flask-hello-world-subdomain.your-domain.com
export SITE_NAME=flask-hello-world
export NGINX_CONFIG_SNIPPET=flask-hello-world

docker-machine ssh $(docker-machine active) \
    sudo /usr/local/src/docker-machine-server/ubuntu/add_nginx_site.sh ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET}
```

Verify

```
curl https://${SERVER_NAME}
```


## Deploy Rancher to create a Kubernetes cluster

Connect to the relevant Docker Machine

```
eval $(docker-machine env RANCHER_DOCKER_MACHINE_NAME)
```

Create the Rancher data directory

```
docker-machine ssh $(docker-machine active) sudo mkdir -p /var/lib/rancher
```

Start Rancher (recommended a machine of at least 2GB ram and 2 CPU cores)

```
docker run -d --name rancher --restart unless-stopped -p 8000:80 \
              -v "/var/lib/rancher:/var/lib/rancher" rancher/rancher:stable
```

Register the SSL certificate and setup domain for Rancher

Add Rancher to Nginx

```
export SERVER_NAME=rancher.your-domain.com
export SITE_NAME=rancher
export NGINX_CONFIG_SNIPPET=rancher

echo 'location / {
    proxy_pass http://localhost:8000;
    include snippets/http2_proxy.conf;
}' | docker-machine ssh $(docker-machine active) sudo tee /etc/nginx/snippets/${NGINX_CONFIG_SNIPPET}.conf &&\
docker-machine ssh $(docker-machine active) \
    sudo /usr/local/src/docker-machine-server/ubuntu/add_nginx_site.sh ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET} &&\
echo Great Success
```
