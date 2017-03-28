#!/bin/bash

# create new cert using letsencrypt for use with haproxy.
# - aborts if folder /etc/letsencrypt/live/domain.tld/ exists
# - creates haproxy.pem file in /etc/letsencrypt/live/domain.tld/
# - softlinks the haproxy.pem file to /etc/letsencrypt/haproxy-certs/domain.tld.pem
# - soft restart haproxy
#
# usage:
# sudo ./cert-create-haproxy.sh domain.tld domain2.tld ...

###################
## configuration ##
###################

EMAIL="your_le_account@email.com"

LE_CLIENT="/usr/local/bin/certbot-auto"

HAPROXY_RELOAD_CMD="service haproxy reload"

WEBROOT="/var/lib/haproxy"

HAP_CERT_ROOT="/etc/letsencrypt/haproxy-certs"

# Enable to redirect output to logfile (for silent cron jobs)
# LOGFILE="/var/log/certrenewal.log"

######################
## utility function ##
######################

function issueCert {
  $LE_CLIENT certonly --text --webroot --webroot-path ${WEBROOT} --renew-by-default --agree-tos --email ${EMAIL} $1 &>/dev/null
  return $?
}

function createProxyCert {
cat /etc/letsencrypt/live/www.example.com/privkey.pem \
  /etc/letsencrypt/live/www.example.com/fullchain.pem \
  | sudo tee /etc/letsencrypt/live/www.example.com/haproxy.pem >/dev/null
}

function logger_error {
  if [ -n "${LOGFILE}" ]
  then
    echo "[error] [$(date +'%d.%m.%y - %H:%M')] ${1}" >> ${LOGFILE}
  fi
  >&2 echo "[error] ${1}"
}

function logger_info {
  if [ -n "${LOGFILE}" ]
  then
    echo "[info] [$(date +'%d.%m.%y - %H:%M')] ${1}" >> ${LOGFILE}
  else
    echo "[info] ${1}"
  fi
}

##################
## main routine ##
##################

le_cert_root="/etc/letsencrypt/live"

if [ ! -d ${le_cert_root} ]; then
  logger_error "${le_cert_root} does not exist!"
  exit 1
fi

if [ ! -d ${HAP_CERT_ROOT} ]; then
  logger_error "${HAP_CERT_ROOT} does not exist!"
  exit 1
fi

created_certs=()
exitcode=0
for domain in "$@"
do
  # TODO: allow for alternative name
  
  le_domain_cert_root="${le_cert_root}/${domain}"
  if [ -d ${le_domain_cert_root} ]; then
    logger_error "skipping ${domain}: ${le_domain_cert_root} already exists, renew instead!"
    continue
  fi
  
  # TODO: allow for alternative name
  $domains="-d ${domain}"
  
  issueCert "${domains}"
  if [ $? -ne 0 ]
  then
    logger_error "${domain}: failed to create certificate! check /var/log/letsencrypt/letsencrypt.log!"
    exitcode=1
  else
    created_certs+=("$domain")
    logger_info "${domain}: created certificate"
  fi

done


# create haproxy.pem file(s)
for domain in ${created_certs[@]}; do
  cat ${le_cert_root}/${domain}/privkey.pem ${le_cert_root}/${domain}/fullchain.pem | tee ${le_cert_root}/${domain}/haproxy.pem >/dev/null
  ln -s ${le_cert_root}/${domain}/haproxy.pem ${HAP_CERT_ROOT}/${domain}.pem
  if [ $? -ne 0 ]; then
    logger_error "${domain}: failed to create haproxy.pem file!"
    continue
  fi
done

# soft-restart haproxy
if [ "${#renewed_certs[@]}" -gt 0 ]; then
  $HAPROXY_RELOAD_CMD
  if [ $? -ne 0 ]; then
    logger_error "failed to reload haproxy!"
    exit 1
  fi
fi

exit ${exitcode}
