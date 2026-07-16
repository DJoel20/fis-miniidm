#!/bin/bash
# Comandos de referencia usados para crear la CA raiz y emitir certificados de servidor.
# NO commitear ca.key ni ningun *.key real generado con estos comandos.

# 1. Clave y certificado autofirmado de la CA raiz (ECDSA P-256)
openssl ecparam -name prime256v1 -genkey -noout -out ca.key
openssl req -x509 -new -key ca.key -sha256 -days 3650 -out ca.crt \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS EPN/CN=Servidor CA Raiz"

# 2. Clave y CSR para un servidor (ejemplo: LDAP master)
openssl ecparam -name prime256v1 -genkey -noout -out ldap1.key
openssl req -new -key ldap1.key -out ldap1.csr \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS EPN/CN=ldap1.fis.epn.edu.ec"

# 3. Firma del certificado del servidor con la CA
openssl x509 -req -in ldap1.csr -CA ca.crt -CAkey ca.key -CAcreateserial \
  -out ldap1.crt -sha256 -days 365

# 4. Verificacion
openssl x509 -in ca.crt -noout -subject -issuer -dates
openssl x509 -in ca.crt -noout -text | grep -E "Signature Algorithm|Public Key Algorithm"
openssl s_client -connect 127.0.0.1:636 -showcerts </dev/null 2>/dev/null | openssl x509 -noout -subject -issuer

# El mismo procedimiento (pasos 2-3) se repite para ldap2, el KDC (si aplica) y
# webserver.fis.epn.edu.ec, reutilizando siempre ca.crt / ca.key como firmante.
