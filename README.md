# Docker Machine Server

Scripts and documentation for rapid deployment and management of servers running on Docker Machines.

## Installation

[Install Docker Machine](https://docs.docker.com/machine/install-machine/)

## Create a machine

Create a cloud account for one of the [supported drivers](https://docs.docker.com/machine/drivers/) or [3rd party drivers](https://github.com/docker/docker.github.io/blob/master/machine/AVAILABLE_DRIVER_PLUGINS.md).

Follow the relevant driver documentation to create a machine with a recent Ubuntu operating system.

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
    'bash -c "curl -L https://raw.githubusercontent.com/OriHoch/docker-machine-server/master/ubuntu/install_nginx_ssl.sh | sudo bash"'
```

Get the server's IP:

```
docker-machine ip $(docker-machine active)
```

Register a subdomain to point to that IP

Register the SSL certificate (set suitable values for the environment variables):

```
export LETSENCRYPT_EMAIL=your@email.com
export LETSENCRYPT_DOMAIN=subdomain.your-domain.com

docker-machine ssh $(docker-machine active) \
    'bash -c "curl -L https://raw.githubusercontent.com/OriHoch/docker-machine-server/master/ubuntu/setup_ssl.sh | sudo bash -s '${LETSENCRYPT_EMAIL} ${LETSENCRYPT_DOMAIN}'"'
```

Deploy your app, for this example we will build and run a simple Python Flask web-app:

```
mkdir -p flask-hello-world &&\
echo 'from flask import Flask
app = Flask(__name__)
@app.route("/")
def hello():
    return "Hello World!\n"' > flask-hello-world/hello.py &&\
echo 'FROM python
RUN python3 -m pip install flask
COPY hello.py .
ENV FLASK_APP=hello.py
ENTRYPOINT ["flask", "run"]' > flask-hello-world/Dockerfile &&\
docker build -t flask-hello-world flask-hello-world &&\
( docker rm --force flask-hello-world || true ) &&\
docker run -d --name flask-hello-world -p 5000:5000 flask-hello-world --host 0.0.0.0
```

Verify that the app is running:

```
docker-machine ssh $(docker-machine active) curl -s localhost:5000
```

Create the nginx configuration on the server at `/etc/nginx/snippets/flask-hello-world`

This example creates a proxy forwarding configuration supporting http/2 for advanced workloads, you can use simpler nginx configurations depending on your requirements

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

Add the flask-hello-world app to Nginx, you may use different subdomains - they will all share the SSL certificate

```
export LETSENCRYPT_DOMAIN=subdomain.your-domain.com
export SITE_NAME=flask-hello-world
export NGINX_CONFIG_SNIPPET=flask-hello-world

docker-machine ssh $(docker-machine active) \
    'bash -c "curl -L https://raw.githubusercontent.com/OriHoch/docker-machine-server/master/ubuntu/add_nginx_site.sh | sudo bash -s '${LETSENCRYPT_DOMAIN} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET}'"'
```
