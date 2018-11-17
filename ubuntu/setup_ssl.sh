#!/usr/bin/env bash

LETSENCRYPT_EMAIL="${1}"
CERTBOT_PARAMS="${2}"
LETSENCRYPT_DOMAIN="${3}"

( [ -z "${LETSENCRYPT_EMAIL}" ] || [ -z "${CERTBOT_PARAMS}" ] || [ -z "${LETSENCRYPT_DOMAIN}" ] ) \
    && echo missing required arguments && exit 1

certbot certonly --agree-tos --email ${LETSENCRYPT_EMAIL} --webroot -w /var/lib/letsencrypt/ -d ${CERTBOT_PARAMS} &&\
echo "
  ssl_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/fullchain.pem;
  ssl_certificate_key /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/privkey.pem;
  ssl_trusted_certificate /etc/letsencrypt/live/${LETSENCRYPT_DOMAIN}/chain.pem;
" | tee /etc/nginx/snippets/letsencrypt_certs.conf
[ "$?" != "0" ] && exit 1

echo Great Success!
exit 0
