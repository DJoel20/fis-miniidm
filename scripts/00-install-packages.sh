#!/bin/bash
# 00-install-packages.sh
# Instala todos los paquetes necesarios para el stack completo.
set -e
source "$(dirname "$0")/lib/common.sh"

step "Actualizando indices de paquetes"
sudo apt update

step "Instalando OpenLDAP, Kerberos, PKI, HAProxy, Apache, Docker"
sudo DEBIAN_FRONTEND=noninteractive apt install -y \
    slapd ldap-utils \
    krb5-kdc krb5-admin-server krb5-kpropd krb5-user krb5-kdc-ldap \
    openssl \
    haproxy \
    apache2 libapache2-mod-auth-gssapi \
    docker.io \
    net-tools iptables faketime \
    curl wget

step "Habilitando Docker"
sudo systemctl enable --now docker
sudo usermod -aG docker "$USER" || true

step "Paquetes instalados"
echo "IMPORTANTE: si este es el primer uso de docker con tu usuario, cierra y"
echo "vuelve a abrir la terminal (o corre 'newgrp docker') antes de continuar con 06/07."
