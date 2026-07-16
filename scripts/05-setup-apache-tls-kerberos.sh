#!/bin/bash
# 05-setup-apache-tls-kerberos.sh
# Publica un endpoint protegido con Kerberos (SPNEGO) sobre TLS.
# Debe ejecutarse DESPUES de 01 (PKI) y 03 (Kerberos primario).
set -e
source "$(dirname "$0")/lib/common.sh"

PKI_DIR="/etc/ssl/fis-pki"

step "Habilitando modulos de Apache"
sudo a2enmod ssl auth_gssapi headers

step "Creando el contenido web protegido"
sudo mkdir -p /var/www/html/seguro
sudo tee /var/www/html/seguro/index.html > /dev/null <<'EOF'
<h1>Acceso Concedido - Kerberos Autenticado</h1>
EOF

step "Generando keytab de Apache para HTTP/webserver.${FIS_DOMAIN}"
sudo kadmin.local -q "ktadd -k /etc/apache2/http.keytab HTTP/webserver.${FIS_DOMAIN}@${REALM}"
sudo chown root:www-data /etc/apache2/http.keytab
sudo chmod 640 /etc/apache2/http.keytab

step "Desplegando el vhost"
sudo cp "$(dirname "$0")/../apache/seguro.conf" /etc/apache2/sites-available/seguro.conf
sudo sed -i "s#/etc/ssl/fis-pki#${PKI_DIR}#g" /etc/apache2/sites-available/seguro.conf
sudo a2ensite seguro.conf
sudo a2dissite 000-default.conf 2>/dev/null || true

step "Reiniciando Apache"
sudo systemctl restart apache2
sudo systemctl status apache2 --no-pager | head -5

step "Agregando webserver.${FIS_DOMAIN} a /etc/hosts (una linea, requisito para SPNEGO)"
add_hosts_entry "$(get_host_ip)" "webserver.${FIS_DOMAIN}"

step "Verificacion (necesita un ticket Kerberos valido: kinit jperez@${REALM})"
echo "curl -v --negotiate -u : https://webserver.${FIS_DOMAIN}/seguro/ -k"
echo "Debe responder 200 OK con 'Acceso Concedido - Kerberos Autenticado' sin pedir password."
