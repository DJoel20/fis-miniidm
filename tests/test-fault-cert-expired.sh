#!/bin/bash
# Punto 9.3: Expiracion de certificados
# Reemplaza el certificado valido de Apache con uno vencido, usando la MISMA
# clave privada real (para no romper el TLS por mismatch de clave/certificado).
set -e

CERT_DIR="/etc/ssl/fis-pki/certs"
CA_DIR="/etc/ssl/fis-pki/ca"

echo "== Backup del certificado valido =="
sudo cp "$CERT_DIR/webserver.crt" "$CERT_DIR/webserver.crt.backup"

echo "== Generando CSR con la clave privada real del servidor =="
sudo openssl req -new -key "$CERT_DIR/webserver.key" -out /tmp/webserver_expired.csr \
  -subj "/C=EC/ST=Pichincha/L=Quito/O=FIS EPN/CN=webserver.fis.epn.edu.ec"

echo "== Firmando con fechas vencidas (faketime, ano 2020) =="
sudo faketime '2020-01-01 00:00:00' openssl x509 -req -in /tmp/webserver_expired.csr \
  -CA "$CA_DIR/ca.crt" -CAkey "$CA_DIR/ca.key" -CAcreateserial \
  -out /tmp/webserver_expired.crt -sha256 -days 30

openssl x509 -in /tmp/webserver_expired.crt -noout -dates

echo "== Instalando el certificado expirado =="
sudo cp /tmp/webserver_expired.crt "$CERT_DIR/webserver.crt"
sudo systemctl restart apache2

echo "== Probando con curl (debe rechazar por expiracion) =="
curl --cacert "$CA_DIR/ca.crt" https://webserver.fis.epn.edu.ec/ || echo "Rechazado correctamente (esperado)"

echo "== Restaurando el certificado valido =="
sudo cp "$CERT_DIR/webserver.crt.backup" "$CERT_DIR/webserver.crt"
sudo systemctl restart apache2
curl --cacert "$CA_DIR/ca.crt" -s -o /dev/null -w "HTTP status tras restaurar: %{http_code}\n" https://webserver.fis.epn.edu.ec/
