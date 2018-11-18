# Docker Machine Server Apps Catalog

Catalog of applications / services to deploy on docker-machine-server

## Create a Kubernetes cluster using Rancher

[Rancher](https://rancher.com/) allows to create a Kubernetes cluster using Docker Machines

Connect to the relevant Docker Machine

Recommended - a machine with at least 2GB ram and 2 CPU cores

```
eval $(docker-machine env RANCHER_DOCKER_MACHINE_NAME)
```

Create the Rancher data directory

```
docker-machine ssh $(docker-machine active) sudo mkdir -p /var/lib/rancher
```

Start Rancher

```
docker run -d --name rancher --restart unless-stopped -p 8000:80 \
           -v "/var/lib/rancher:/var/lib/rancher" rancher/rancher:stable
```

Register DNS and update the SSL certificate to include Rancher subdomain

```
ADD_CERTBOT_DOMAIN="rancher.your-domain.com"

docker-machine ssh $(docker-machine active) sudo docker-machine-server add_certbot_domain ${ADD_CERTBOT_DOMAIN}
```

Add Rancher to Nginx

```
SERVER_NAME=rancher.your-domain.com
SITE_NAME=rancher
NGINX_CONFIG_SNIPPET=rancher
PROXY_PASS_PORT=8000

docker-machine ssh $(docker-machine active) sudo docker-machine-server add_nginx_site_http2_proxy ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET} ${PROXY_PASS_PORT}
```

Activate via the web-ui

You can now create cluster via the web-ui

Rancher includes a CLI, to install - click on the lower right corner in Rancher web-ui - Download CLI

Extract and place in PATH

```
tar -xzf ~/Downloads/rancher-linux-amd64-v2.0.5.tar.gz &&\
sudo mv rancher-v2.0.5/rancher /usr/local/bin/ &&\
rm -rf rancher-v2.0.5
```

Verify rancher CLI version

```
rancher --version
```

In the Rancher web-ui, click on the user profile image (top right) and on API & Keys

Create a new Key

Login to the Rancher server using the key:

```
rancher login --token <BEARER_TOKEN> <RANCHER_ENDPOINT_URL>
```

## Deploy Jenkins

[Jenkins](https://jenkins.io/)

Connect to the relevant Docker Machine with at least 1GB ram and 1 CPU core

```
eval $(docker-machine env RANCHER_DOCKER_MACHINE_NAME)
```

Create the jenkins home directory

```
docker-machine ssh $(docker-machine active) 'sudo bash -c "mkdir -p /var/jenkins_home && chown -r 1000:1000 /var/jenkins_home"'
```

Create and build a Dockerfile for Jenkins with some useful plugins and system dependencies:

```
echo 'FROM jenkins/jenkins:lts
RUN /usr/local/bin/install-plugins.sh \
        build-timeout envfile copyartifact extensible-choice-parameter fail-the-build file-operations \
        filesystem-list-parameter fstrigger generic-webhook-trigger git-parameter github-branch-source \
        global-variable-string-parameter http_request jobgenerator join managed-scripts matrix-combinations-parameter \
        persistent-parameter workflow-aggregator pipeline-github-lib python ssh-slaves timestamper urltrigger \
        ws-cleanup
USER root
RUN curl -L "https://github.com/docker/compose/releases/download/1.23.1/docker-compose-$(uname -s)-$(uname -m)" -o /usr/local/bin/docker-compose
RUN apt-get update && apt-get install -y apt-transport-https ca-certificates curl gnupg2 software-properties-common
RUN curl -fsSL https://download.docker.com/linux/debian/gpg | apt-key add - && apt-key fingerprint 0EBFCD88 &&\
    add-apt-repository "deb [arch=amd64] https://download.docker.com/linux/debian $(lsb_release -cs) stable" &&\
    apt-get update && apt-get install -y docker-ce
RUN chmod +x /usr/local/bin/docker-compose && echo "jenkins ALL=NOPASSWD: ALL" >> /etc/sudoers
RUN apt update && apt install -y python3-pip
RUN python3 -m pip install pyyaml
USER jenkins
RUN /usr/local/bin/install-plugins.sh rebuild' > .jenkins.Dockerfile &&\
docker build -t jenkins -f .jenkins.Dockerfile .
```

Run Jenkins

```
docker run -d --name jenkins -p 8080:8080 -v /var/jenkins_home:/var/jenkins_home jenkins
```

Register DNS and update the SSL certificate to include the Jenkins subdomain

```
ADD_CERTBOT_DOMAIN="jenkins.your-domain.com"

docker-machine ssh $(docker-machine active) sudo docker-machine-server add_certbot_domain ${ADD_CERTBOT_DOMAIN}
```

Add Rancher to Nginx

```
SERVER_NAME=jenkins.your-domain.com
SITE_NAME=jenkins
NGINX_CONFIG_SNIPPET=jenkins
PROXY_PASS_PORT=8080

docker-machine ssh $(docker-machine active) sudo docker-machine-server add_nginx_site_http2_proxy ${SERVER_NAME} ${SITE_NAME} ${NGINX_CONFIG_SNIPPET} ${PROXY_PASS_PORT}
```

Get the admin password

```
docker-machine ssh $(docker-machine active) sudo cat /var/jenkins_home/secrets/initialAdminPassword
```

Activate via the web-ui
