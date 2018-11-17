# Docker Machine Server

Scripts and documentation for rapid deployment and management of servers running on Docker Machines.

## Installation

[Install Docker Machine](https://docs.docker.com/machine/install-machine/)

## Create a machine

Create a cloud account for one of the [supported drivers](https://docs.docker.com/machine/drivers/) or [3rd party drivers](https://github.com/docker/docker.github.io/blob/master/machine/AVAILABLE_DRIVER_PLUGINS.md).

Follow the relevant driver documentation to create a machine with Ubuntu (known to work with 16.04 and 18.04).

Copy the docker-machine-server scripts to the machine:

```
docker-machine ssh $(docker-machine active) \
    'sudo bash -c "rm -rf /opt/docker-machine-server-master && rm -f /opt/master.tar.gz &&\
     mkdir -p /opt && cd /opt &&\
     wget -q https://github.com/OriHoch/docker-machine-server/archive/master.tar.gz &&\
     tar -xzf master.tar.gz && chmod +x /opt/docker-machine-server-master/ubuntu/*.sh &&\
     echo Great Success"'
```

## Deploy an app and expose via SSL

Set the target machine as the active Docker Machine

```

export TARGET_DOCKER_MACHINE_NAME=your-docker-machine

eval $(docker-machine env ${TARGET_DOCKER_MACHINE_NAME}) &&\
docker-machine active
```

Install and configure Nginx and Let's Encrypt

```
docker-machine ssh $(docker-machine active) \
    sudo /opt/docker-machine-server-master/ubuntu/install_nginx_ssl.sh
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
    sudo /opt/docker-machine-server-master/ubuntu/setup_ssl.sh ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAINS}
```

Deploy your app, the docker-machine-server code includes an example web-app for testing

Build and run the web-app

```
docker-machine ssh $(docker-machine active) \
    sudo docker build -t flask-hello-world /opt/docker-machine-server-master/flask-hello-world &&\
docker-machine ssh $(docker-machine active) \
    sudo docker run -d --name flask-hello-world -p 5000:5000 flask-hello-world --host 0.0.0.0
```

Verify that the app is running:

```
docker-machine ssh $(docker-machine active) curl -s localhost:5000
```

Create the nginx configuration on the server at `/etc/nginx/snippets/flask-hello-world`

This example creates a proxy to the flask-hello-world at port 5000:

```
echo 'location / {
    proxy_pass http://localhost:5000;

    proxy_set_header X-Forwarded-For $remote_addr;
    proxy_set_header Host $http_host;
    proxy_set_header X-Forwarded-Proto $scheme;
    proxy_set_header X-Forwarded-Port $server_port;
    proxy_http_version 1.1;
    proxy_set_header Upgrade $http_upgrade;
    proxy_set_header Connection "Upgrade";
    # This allows the ability for the execute shell window to remain open for up to 15 minutes. Without this parameter, the default is 1 minute and will automatically close.
    proxy_read_timeout 900s;
}' | docker-machine ssh $(docker-machine active) sudo tee /etc/nginx/snippets/flask-hello-world.conf
```

Add the flask-hello-world app to Nginx

```
export SERVER_NAME=flask-hello-world-subdomain.your-domain.com
export SITE_NAME=flask-hello-world
export NGINX_CONFIG_SNIPPET=flask-hello-world

docker-machine ssh $(docker-machine active) \
    sudo /opt/docker-machine-server-master/ubuntu/add_nginx_site.sh ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET}
```
