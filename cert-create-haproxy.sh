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

CERTROOT="/etc/letsencrypt/live"

HAP_CERT_ROOT="/etc/letsencrypt/haproxy-certs"

# Enable to redirect output to logfile (for silent cron jobs)
LOGFILE="/var/log/letsencrypt/certcreate.log"

######################
## utility function ##
######################

function issueCert {
  $LE_CLIENT certonly --text --webroot --webroot-path ${WEBROOT} --renew-by-default --agree-tos --email ${EMAIL} $1 &> ${LOGFILE}
  return $?
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

if [ ! -d ${CERTROOT} ]; then
  logger_error "${CERTROOT} does not exist!"
  exit 1
fi

if [ ! -d ${HAP_CERT_ROOT} ]; then
  logger_error "${HAP_CERT_ROOT} does not exist!"
  exit 1
fi

created_certs=()
exitcode=0
for domains in "$@"
do
  # allow for alternative name. Use the first one listed as the main domain.
  maindomain="";
  domainstocreate="";
  for domainname in $domains
  do
    if [ "${maindomain}" == "" ]; then maindomain="$domainname"; fi
    domainstocreate="${domainstocreate} -d ${domainname}"
  done
  
  logger_info "creating cert for ${maindomain}: ${domainstocreate}"
  
  le_domain_cert_root="${CERTROOT}/${maindomain}"
  if [ -d ${le_domain_cert_root} ]; then
    logger_error "skipping ${maindomain}: ${le_domain_cert_root} already exists, renew instead!"
    continue
  fi

  issueCert "${domainstocreate}"
  
  if [ $? -ne 0 ]
  then
    logger_error "${maindomain}: failed to create certificate! ${LOGFILE}!"
    exitcode=1
  else
    created_certs+=("$maindomain")
    logger_info "${maindomain}: created certificate"
  fi

done


# create haproxy.pem file(s)
for domain in ${created_certs[@]}; do
  cat ${CERTROOT}/${domain}/privkey.pem ${CERTROOT}/${domain}/fullchain.pem | tee ${CERTROOT}/${domain}/haproxy.pem >/dev/null
  ln -s ${CERTROOT}/${domain}/haproxy.pem ${HAP_CERT_ROOT}/${domain}.pem
  if [ $? -ne 0 ]; then
    logger_error "${domain}: failed to create haproxy.pem file!"
    continue
  fi
done

# soft-restart haproxy
if [ "${#created_certs[@]}" -gt 0 ]; then
  $HAPROXY_RELOAD_CMD
  if [ $? -ne 0 ]; then
    logger_error "failed to reload haproxy!"
    exit 1
  fi
fi

exit ${exitcode}
