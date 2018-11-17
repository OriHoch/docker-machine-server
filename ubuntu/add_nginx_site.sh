#!/usr/bin/env bash

LETSENCRYPT_DOMAIN="${1}"
SITE_NAME="${2}"
NGINX_CONFIG_SNIPPET="${3}"

echo 'server {
  listen 80;
  listen    [::]:80;
  server_name '${LETSENCRYPT_DOMAIN}';
  include snippets/letsencrypt.conf;
  return 301 https://$host$request_uri;
}
server {
  listen 443 ssl http2;
  listen [::]:443 ssl http2;
  server_name '${LETSENCRYPT_DOMAIN}';
  include snippets/letsencrypt_certs.conf;
  include snippets/ssl.conf;
  include snippets/letsencrypt.conf;
  include snippets/'${NGINX_CONFIG_SNIPPET}'.conf;
}
' | tee /etc/nginx/sites-enabled/${SITE_NAME} &&\
systemctl restart nginx
[ "$?" != "0" ] && exit 1

echo Great Success!
exit 0
