# Docker Machine Server

Scripts and documentation for rapid deployment and management of servers running on Docker Machines.

## Installation

[Install Docker Machine](https://docs.docker.com/machine/install-machine/)

## Create a machine

Create a cloud account for one of the [supported drivers](https://docs.docker.com/machine/drivers/) or [3rd party drivers](https://github.com/docker/docker.github.io/blob/master/machine/AVAILABLE_DRIVER_PLUGINS.md).

Follow the relevant driver documentation to create a machine with Ubuntu 18.04

Make sure you are connected to the relevant machine

```
eval $(docker-machine env YOUR_DOCKER_MACHINE_NAME) &&\
docker-machine active
```

Choose a Docker Machine server [release](https://github.com/OriHoch/docker-machine-server/releases) to deploy and set in environment variable

```
DOCKER_MACHINE_SERVER_VERSION=0.0.1
```

Initialize docker-machine-server on the active machine

```
curl -L https://raw.githubusercontent.com/OriHoch/docker-machine-server/v${DOCKER_MACHINE_SERVER_VERSION}/docker-machine-server.sh \
    | bash -s $DOCKER_MACHINE_SERVER_VERSION
```

If you want to install latest dev version of docker-machine-server - clone the code, and run the following from the docker-machine-server project directory: `./docker-machine-server.sh init_dev`

## Deploy an app and expose via SSL

Install and configure Nginx and Let's Encrypt (will delete existing configurations)

```
docker-machine ssh $(docker-machine active) sudo docker-machine-server install_nginx_ssl
```

Get the server's IP:

```
docker-machine ip $(docker-machine active)
```

Register a subdomain to point to that IP (for maximal security, add a CAA record: `example.org. CAA 128 issue "letsencrypt.org"`)

Register the SSL certificates (can add additional subdomains later, see below)

```
LETSENCRYPT_EMAIL=your@email.com
CERTBOT_DOMAINS="subdomain1.your-domain.com,subdomain2.your-domain.com"

# this should be the first one of the CERTBOT_DOMAINS
LETSENCRYPT_DOMAIN=subdomain1.your-domain.com

docker-machine ssh $(docker-machine active) sudo docker-machine-server setup_ssl ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAIN}
```

Deploy an app - you can use standard `docker run` while connected to the machine.

The docker-machine-server code includes an example web-app for testing, to use it -
* Clone the docker-machine-server code: `git clone https://github.com/OriHoch/docker-machine-server.git`
* Change to docker-machine-server directory: `cd docker-machine-server`
* Build: `docker build -t flask-hello-world flask-hello-world`
* Run: `docker run -d --name flask-hello-world -p 5000:5000 flask-hello-world --host 0.0.0.0`

Following commands assume your are deploying the Flask app, modify relevant configurations as needed

Verify that the app is running:

```
docker-machine ssh $(docker-machine active) curl -s localhost:5000
```

Add the app to Nginx

```
SERVER_NAME=flask-hello-world.your-domain.com
SITE_NAME=flask-hello-world
NGINX_CONFIG_SNIPPET=flask-hello-world
PROXY_PASS_PORT=5000

docker-machine ssh $(docker-machine active) sudo docker-machine-server add_nginx_site_http2_proxy ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET} ${PROXY_PASS_PORT}
```

Verify

```
curl https://${SERVER_NAME}
```

## Register additional SSL sub/domains

Get list of currently registered domains:

```
docker-machine ssh $(docker-machine active) sudo cat /etc/docker-machine-server/CERTBOT_DOMAINS
```

Get the server's IP:

```
docker-machine ip $(docker-machine active)
```

Set DNS for a subdomain to point to that IP (for maximal security, add a CAA record: `example.org. CAA 128 issue "letsencrypt.org"`)

Register the domain with certbot

```
ADD_CERTBOT_DOMAIN="my-subdomain.your-domain.com"

docker-machine ssh $(docker-machine active) sudo docker-machine-server add_certbot_domain ${ADD_CERTBOT_DOMAIN}
```

## docker-machine-server apps

See the [Apps Catalog](APPS.md) for guides to install applications / services on docker-machine-server.
