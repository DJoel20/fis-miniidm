#!/bin/bash
# 01-setup-pki.sh
# Crea la CA raiz (ECDSA) y emite certificados para ldap1, ldap2 y el
# servidor web, todos firmados por la misma CA.
set -e
source "$(dirname "$0")/lib/common.sh"

PKI_DIR="/etc/ssl/fis-pki"

step "Creando estructura de directorios de la PKI en ${PKI_DIR}"
sudo mkdir -p "${PKI_DIR}/ca" "${PKI_DIR}/certs"

step "Generando clave y certificado autofirmado de la CA raiz (ECDSA P-256)"
if [ ! -f "${PKI_DIR}/ca/ca.key" ]; then
    sudo openssl ecparam -name prime256v1 -genkey -noout -out "${PKI_DIR}/ca/ca.key"
    sudo openssl req -x509 -new -key "${PKI_DIR}/ca/ca.key" -sha256 -days 3650 \
        -out "${PKI_DIR}/ca/ca.crt" \
        -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS EPN/CN=Servidor CA Raiz"
else
    echo "La CA ya existe, se reutiliza."
fi

issue_cert() {
    local cn="$1"
    local name="$2"
    step "Emitiendo certificado para ${cn}"
    sudo openssl ecparam -name prime256v1 -genkey -noout -out "${PKI_DIR}/certs/${name}.key"
    sudo openssl req -new -key "${PKI_DIR}/certs/${name}.key" -out "/tmp/${name}.csr" \
        -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS EPN/CN=${cn}"
    sudo openssl x509 -req -in "/tmp/${name}.csr" \
        -CA "${PKI_DIR}/ca/ca.crt" -CAkey "${PKI_DIR}/ca/ca.key" -CAcreateserial \
        -out "${PKI_DIR}/certs/${name}.crt" -sha256 -days 365
    sudo chmod 644 "${PKI_DIR}/certs/${name}.crt"
    sudo chmod 600 "${PKI_DIR}/certs/${name}.key"
}

issue_cert "ldap1.${FIS_DOMAIN}" "ldap1"
issue_cert "ldap2.${FIS_DOMAIN}" "ldap2"
issue_cert "webserver.${FIS_DOMAIN}" "webserver"

step "Verificacion"
openssl x509 -in "${PKI_DIR}/ca/ca.crt" -noout -subject -issuer -dates
openssl x509 -in "${PKI_DIR}/ca/ca.crt" -noout -text | grep -E "Signature Algorithm|Public Key Algorithm"

echo "PKI lista en ${PKI_DIR}"
