.PHONY: setup setup-step-by-step start stop status \
        test-replication test-kdc-failover test-loadbalancer test-faults \
        test-fault-kill9 test-fault-network test-fault-cert test-fault-kdc \
        verify-all monitoring-status clean

SHELL := /bin/bash

setup:
	bash scripts/00-install-packages.sh
	bash scripts/01-setup-pki.sh
	bash scripts/02-setup-ldap-master.sh
	bash scripts/03-setup-kerberos-primary.sh
	bash scripts/04-integrate-ldap-kerberos.sh
	bash scripts/05-setup-apache-tls-kerberos.sh
	bash scripts/06-setup-ldap-replica.sh
	bash scripts/07-setup-kerberos-secondary.sh
	bash scripts/08-setup-haproxy.sh
	bash scripts/09-setup-monitoring.sh
	@echo ""
	@echo "Setup completo."

setup-step-by-step:
	@ls scripts/*.sh | sort

## Levanta todos los servicios (corregido para KDC secundario)
start:
	@echo "--- Liberando puertos ---"
	-sudo fuser -k 2088/tcp 2>/dev/null || true
	-sudo fuser -k 2088/udp 2>/dev/null || true
	
	sudo systemctl start slapd
	sudo systemctl start krb5-kdc krb5-admin-server
	sudo systemctl start apache2
	sudo systemctl start haproxy
	sudo systemctl start prometheus node_exporter grafana-server || true
	sudo systemctl start ldap-repl-check.timer 2>/dev/null || true
	
	docker start ldap2 kdc2 || true
	docker exec ldap2 service slapd start || true
	
	@echo "--- Iniciando KDC secundario manualmente ---"
	# Copia de configuración y arranque en primer plano para asegurar visibilidad
	sudo docker cp /etc/krb5.conf kdc2:/etc/krb5.conf
	# Cargamos base de datos si falta
	@if [ "$$(sudo docker exec kdc2 ls -1 /var/lib/krb5kdc/principal 2>/dev/null)" == "" ]; then \
		sudo docker cp /var/lib/krb5kdc/replica_datatrans kdc2:/tmp/replica_datatrans; \
		sudo docker exec kdc2 /usr/sbin/kdb5_util load /tmp/replica_datatrans; \
	fi
	# Lanzamos el demonio
	sudo docker exec -d kdc2 /usr/sbin/krb5kdc -n -r FIS.EPN.EC -d /var/lib/krb5kdc/principal
	@echo "KDC secundario iniciado en segundo plano."

stop:
	sudo systemctl stop slapd krb5-kdc apache2 haproxy || true
	docker stop ldap2 kdc2 || true

## Muestra el estado (corregido para detectar el KDC en contenedor)
status:
	@echo "--- slapd (LDAP master, :1388) ---"; sudo systemctl is-active slapd
	@echo "--- krb5-kdc (KDC primario) ---"; sudo systemctl is-active krb5-kdc
	@echo "--- apache2 ---"; sudo systemctl is-active apache2
	@echo "--- haproxy ---"; sudo systemctl is-active haproxy
	@echo "--- ldap2 (Docker, replica) ---"; docker exec ldap2 service slapd status || true
	@echo "--- kdc2 (Docker, KDC secundario) ---"; sudo docker exec kdc2 ps aux | grep -q krb5kdc && echo "Running" || echo "Stopped"
	@echo "--- prometheus/grafana/node_exporter ---"; sudo systemctl is-active prometheus grafana-server node_exporter || true
	@echo "--- kprop-sync.timer ---"; sudo systemctl is-active kprop-sync.timer || true

test-replication:
	bash tests/test-ldap-replication.sh
test-kdc-failover:
	bash tests/test-kdc-failover.sh
test-loadbalancer:
	bash tests/test-loadbalancer.sh
test-faults: test-fault-kill9 test-fault-network test-fault-cert test-fault-kdc
test-fault-kill9:
	bash tests/test-fault-kill9.sh
test-fault-network:
	bash tests/test-fault-network-partition.sh
test-fault-cert:
	bash tests/test-fault-cert-expired.sh
test-fault-kdc:
	bash tests/test-fault-kdc-down.sh
verify-all: test-replication test-kdc-failover test-loadbalancer test-faults
	@echo "Todas las pruebas ejecutadas."

monitoring-status:
	curl -s http://localhost:9090/api/v1/targets | grep -o '"job":"[^"]*"' || true
	curl -s http://localhost:3000/api/health || true

clean:
	rm -f /tmp/krb5_test_kdc2.conf /tmp/*.crt /tmp/*.key /tmp/*.csr /tmp/*.ldif
