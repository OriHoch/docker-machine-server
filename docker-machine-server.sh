#!/usr/bin/env bash

info() {
    echo '('$(hostname)'):' $@
}

great_success() {
    info Great Success! $@
}

error() {
    info Error! $@
}

warning() {
    info Warning! $@
}

server_side() {
    [ -e /etc/docker-machine-server/version ]
}

client_side() {
    ! server_side
}

install_nginx_ssl() {
    ! server_side && return 1
    info Installing Nginx and Certbot with strong SSL security &&\
    apt update -y &&\
    apt install -y nginx software-properties-common &&\
    add-apt-repository ppa:certbot/certbot &&\
    apt-get update &&\
    apt-get install -y python-certbot-nginx &&\
    if [ -e /etc/ssl/certs/dhparam.pem ]; then warning Ephemeral Diffie-Hellman key already exists at /etc/ssl/certs/dhparam.pem - delete to recreate
    else info Generating Ephemeral Diffie-Hellman key && openssl dhparam -out /etc/ssl/certs/dhparam.pem 2048; fi &&\
    mkdir -p /var/lib/letsencrypt/.well-known &&\
    chgrp www-data /var/lib/letsencrypt &&\
    chmod g+s /var/lib/letsencrypt &&\
    info Saving /etc/nginx/snippets/letsencrypt.conf &&\
    echo 'location ^~ /.well-known/acme-challenge/ {
  allow all;
  root /var/lib/letsencrypt/;
  default_type "text/plain";
  try_files $uri =404;
}' | tee /etc/nginx/snippets/letsencrypt.conf &&\
    info Saving /etc/nginx/snippets/ssl.conf &&\
    echo 'ssl_dhparam /etc/ssl/certs/dhparam.pem;
ssl_session_timeout 1d;
ssl_session_cache shared:SSL:50m;
ssl_session_tickets off;
ssl_protocols TLSv1 TLSv1.1 TLSv1.2;
# recommended cipher suite for modern browsers
ssl_ciphers 'EECDH+AESGCM:EDH+AESGCM:AES256+EECDH:AES256+EDH';
# cipher suite for backwards compatibility (IE6/windows XP)
# ssl_ciphers 'ECDHE-ECDSA-CHACHA20-POLY1305:ECDHE-RSA-CHACHA20-POLY1305:ECDHE-ECDSA-AES128-GCM-SHA256:ECDHE-RSA-AES128-GCM-SHA256:ECDHE-ECDSA-AES256-GCM-SHA384:ECDHE-RSA-AES256-GCM-SHA384:DHE-RSA-AES128-GCM-SHA256:DHE-RSA-AES256-GCM-SHA384:ECDHE-ECDSA-AES128-SHA256:ECDHE-RSA-AES128-SHA256:ECDHE-ECDSA-AES128-SHA:ECDHE-RSA-AES256-SHA384:ECDHE-RSA-AES128-SHA:ECDHE-ECDSA-AES256-SHA384:ECDHE-ECDSA-AES256-SHA:ECDHE-RSA-AES256-SHA:DHE-RSA-AES128-SHA256:DHE-RSA-AES128-SHA:DHE-RSA-AES256-SHA256:DHE-RSA-AES256-SHA:ECDHE-ECDSA-DES-CBC3-SHA:ECDHE-RSA-DES-CBC3-SHA:EDH-RSA-DES-CBC3-SHA:AES128-GCM-SHA256:AES256-GCM-SHA384:AES128-SHA256:AES256-SHA256:AES128-SHA:AES256-SHA:DES-CBC3-SHA:!DSS';
ssl_prefer_server_ciphers on;
ssl_stapling on;
ssl_stapling_verify on;
resolver 8.8.8.8 8.8.4.4 valid=300s;
resolver_timeout 30s;
add_header Strict-Transport-Security "max-age=15768000; includeSubdomains; preload";
add_header X-Frame-Options SAMEORIGIN;
add_header X-Content-Type-Options nosniff;' | tee /etc/nginx/snippets/ssl.conf &&\
    info Saving /etc/nginx/snippets/http2_proxy.conf &&\
    echo 'proxy_set_header X-Forwarded-For $remote_addr;
proxy_set_header Host $http_host;
proxy_set_header X-Forwarded-Proto $scheme;
proxy_set_header X-Forwarded-Port $server_port;
proxy_http_version 1.1;
proxy_set_header Upgrade $http_upgrade;
proxy_set_header Connection $connection_upgrade;
proxy_read_timeout 900s;' | tee /etc/nginx/snippets/http2_proxy.conf &&\
info Clearing existing Nginx sites from /etc/nginx/sites-enabled &&\
rm -f /etc/nginx/sites-enabled/* &&\
info Saving /etc/nginx/sites-enabled/default &&\
echo '
map $http_upgrade $connection_upgrade {
    default Upgrade;
    '"''"'      close;
}
server {
  listen 80;
  server_name _;
  include snippets/letsencrypt.conf;
  location / {
      return 200 '"'it works!'"';
      add_header Content-Type text/plain;
  }
}' | tee /etc/nginx/sites-enabled/default &&\
    info Verifying certbot renewal systemd timer &&\
    systemctl list-timers | grep certbot &&\
    cat /lib/systemd/system/certbot.timer &&\
    info Restarting Nginx &&\
    systemctl restart nginx
    [ "$?" != "0" ] && error Failed to install strong security Nginx and Certbot && return 1
    great_success && return 0
}

setup_ssl() {
    ! server_side && return 1
    local LETSENCRYPT_EMAIL="${1}"
    local CERTBOT_DOMAINS="${2}"
    local LETSENCRYPT_DOMAIN="${3}"
    ( [ -z "${LETSENCRYPT_EMAIL}" ] || [ -z "${CERTBOT_DOMAINS}" ] || [ -z "${LETSENCRYPT_DOMAIN}" ] ) \
        && error missing required arguments && return 1
    info Setting up SSL &&\
    info LETSENCRYPT_EMAIL=${LETSENCRYPT_EMAIL} CERTBOT_DOMAINS=${CERTBOT_DOMAINS} LETSENCRYPT_DOMAIN=${LETSENCRYPT_DOMAIN} &&\
    certbot certonly --agree-tos --email ${LETSENCRYPT_EMAIL} --webroot -w /var/lib/letsencrypt/ -d ${CERTBOT_DOMAINS} &&\
    echo "ssl_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/fullchain.pem;
ssl_certificate_key /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/privkey.pem;
ssl_trusted_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/chain.pem;" \
    | tee /etc/nginx/snippets/letsencrypt_certs.conf &&\
    echo "${LETSENCRYPT_EMAIL}" > /etc/docker-machine-server/LETSENCRYPT_EMAIL &&\
    echo "${LETSENCRYPT_DOMAIN}" > /etc/docker-machine-server/LETSENCRYPT_DOMAIN &&\
    echo "${CERTBOT_DOMAINS}" > /etc/docker-machine-server/CERTBOT_DOMAINS &&\
    [ "$?" != "0" ] && error Failed to setup SSL && return 1
    sudo systemctl restart nginx
    great_success && return 0
}

add_certbot_domain() {
    ! server_side && return 1
    ( ! [ -e /etc/docker-machine-server/LETSENCRYPT_EMAIL ] || ! [ -e /etc/docker-machine-server/LETSENCRYPT_DOMAIN ] || ! [ -e /etc/docker-machine-server/CERTBOT_DOMAINS ] ) \
        && error Must setup SSL before adding domains && return 1
    local LETSENCRYPT_EMAIL=`cat /etc/docker-machine-server/LETSENCRYPT_EMAIL`
    local LETSENCRYPT_DOMAIN=`cat /etc/docker-machine-server/LETSENCRYPT_DOMAIN`
    local CERTBOT_DOMAINS=`cat /etc/docker-machine-server/CERTBOT_DOMAINS`
    local DOMAIN="${1}"
    echo "${CERTBOT_DOMAINS}" | grep ${DOMAIN} && error Domain ${DOMAIN} already included in CERTBOT_DOMAINS && return 1
    CERTBOT_DOMAINS="${CERTBOT_DOMAINS},${DOMAIN}"
    ! setup_ssl ${LETSENCRYPT_EMAIL} ${CERTBOT_DOMAINS} ${LETSENCRYPT_DOMAIN} && return 1
    return 0
}

add_nginx_site() {
    ! server_side && return 1
    local SERVER_NAME="${1}"
    local SITE_NAME="${2}"
    local NGINX_CONFIG_SNIPPET="${3}"
    ( [ -z "${SERVER_NAME}" ] || [ -z "${SITE_NAME}" ] || [ -z "${NGINX_CONFIG_SNIPPET}" ] ) \
        && error missing required arguments && return 1
    info Adding nginx Site &&\
    info SERVER_NAME=${SERVER_NAME} SITE_NAME=${SITE_NAME} NGINX_CONFIG_SNIPPET=${NGINX_CONFIG_SNIPPET} &&\
    info Saving /etc/nginx/sites-enabled/${SITE_NAME} &&\
    echo '
map $http_upgrade $connection_upgrade {
    default Upgrade;
    '"''"'      close;
}
server {
  listen 80;
  listen    [::]:80;
  server_name '${SERVER_NAME}';
  include snippets/letsencrypt.conf;
  return 301 https://$host$request_uri;
}
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name '${SERVER_NAME}';
  include snippets/letsencrypt_certs.conf;
  include snippets/ssl.conf;
  include snippets/letsencrypt.conf;
  include snippets/'${NGINX_CONFIG_SNIPPET}'.conf;
}' | tee /etc/nginx/sites-enabled/${SITE_NAME} &&\
    info Restarting Nginx &&\
    systemctl restart nginx
    [ "$?" != "0" ] && error Failed to add Nginx site && return 1
    great_success && return 0
}

add_nginx_site_http2_proxy() {
    ! server_side && return 1
    local SERVER_NAME="${1}"
    local SITE_NAME="${2}"
    local NGINX_CONFIG_SNIPPET="${3}"
    local PROXY_PASS_PORT="${4}"
    ( [ -z "${SERVER_NAME}" ] || [ -z "${SITE_NAME}" ] || [ -z "${NGINX_CONFIG_SNIPPET}" ] || [ -z "${PROXY_PASS_PORT}" ] ) \
        && error missing required arguments && return 1
    info Saving /etc/nginx/snippets/${NGINX_CONFIG_SNIPPET}.conf &&\
    echo "location / {
  proxy_pass http://localhost:${PROXY_PASS_PORT};
  include snippets/http2_proxy.conf;
}" | sudo tee /etc/nginx/snippets/${NGINX_CONFIG_SNIPPET}.conf &&\
    add_nginx_site "${SERVER_NAME}" "${SITE_NAME}" "${NGINX_CONFIG_SNIPPET}"
}

init() {
    ! client_side && return 1
    ! local ACTIVE_DOCKER_MACHINE=`docker-machine active` && return 1
    local DOCKER_MACHINE_SERVER_VERSION="${1}"
    info Initializing Docker Machine ${ACTIVE_DOCKER_MACHINE} with docker-machine-server v${DOCKER_MACHINE_SERVER_VERSION} &&\
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'sudo bash -c "
            TEMPDIR=`mktemp -d` && cd \$TEMPDIR &&\
            wget -q https://github.com/OriHoch/docker-machine-server/archive/v'${DOCKER_MACHINE_SERVER_VERSION}'.tar.gz &&\
            tar -xzf 'v${DOCKER_MACHINE_SERVER_VERSION}'.tar.gz &&\
            rm -rf /usr/local/src/docker-machine-server && mkdir -p /usr/local/src/docker-machine-server &&\
            cp -rf docker-machine-server-'${DOCKER_MACHINE_SERVER_VERSION}'/* /usr/local/src/docker-machine-server/ &&\
            cp -f /usr/local/src/docker-machine-server/docker-machine-server.sh /usr/local/bin/docker-machine-server &&\
            chmod +x /usr/local/bin/docker-machine-server &&\
            mkdir -p /etc/docker-machine-server && echo '${DOCKER_MACHINE_SERVER_VERSION}' > /etc/docker-machine-server/version
        "'
    [ "$?" != "0" ] && error Failed to initialize docker-machine-server && return 1
    great_success && return 0
}

init_dev() {
    ! client_side && return 1
    ! local ACTIVE_DOCKER_MACHINE=`docker-machine active` && return 1
    ! [ -e ./docker-machine-server.sh ] && error init_dev must run from docker-machine-server project directory && return 1
    info Syncing local directory to Docker Machine ${ACTIVE_DOCKER_MACHINE} &&\
    docker-machine scp -q -d -r . ${ACTIVE_DOCKER_MACHINE}:/usr/local/src/docker-machine-server/ &&\
    docker-machine ssh ${ACTIVE_DOCKER_MACHINE} \
        'sudo bash -c "
            cp -f /usr/local/src/docker-machine-server/docker-machine-server.sh /usr/local/bin/docker-machine-server &&\
            chmod +x /usr/local/bin/docker-machine-server &&\
            mkdir -p /etc/docker-machine-server && echo '0.0.0' > /etc/docker-machine-server/version
        "'
    [ "$?" != "0" ] && error Failed to initialize docker-machine-server && return 1
    great_success && return 0
}

eval "$@"
