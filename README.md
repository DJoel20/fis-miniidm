# FIS MiniIdM — Infraestructura de Identidad Segura

Proyecto de infraestructura de identidad para la FIS (EPN): OpenLDAP, PKI con ECDSA,
Kerberos (MIT), alta disponibilidad (replicacion LDAP + KDC secundario + balanceo con
HAProxy), inyeccion de fallos y monitoreo con Prometheus/Grafana.

Informe completo: `docs/AnacichaD-MiniIdM.pdf`

## Arquitectura

```
                    Servidor CA Raiz (ECDSA, self-signed)
                              |
        +---------------------+----------------------+
        |                                             |
   LDAP Master (ldap1:1388)  <--syncrepl-->   LDAP Replica (ldap2, Docker, :1389)
        |                                             |
        +---------------- HAProxy :389 -------------->+
                    (ldap.fis.epn.edu.ec)

   KDC Primario (host)  <--kprop/kpropd-->   KDC Secundario (kdc2, Docker, :2088)

   Apache + mod_auth_gssapi (webserver.fis.epn.edu.ec:443, TLS + Kerberos SPNEGO)

   Prometheus + node_exporter + HAProxy exporter + script de replication lag -> Grafana
```

Realm Kerberos: `FIS.EPN.EC` | DIT LDAP: `dc=fis,dc=epn,dc=ec`

## Estructura del repositorio

```
.
├── README.md
├── Makefile
├── docs/
│   └── AnacichaD-MiniIdM.pdf        # informe final
├── scripts/                          # instalacion completa desde cero, en orden
│   ├── lib/common.sh
│   ├── 00-install-packages.sh
│   ├── 01-setup-pki.sh
│   ├── 02-setup-ldap-master.sh
│   ├── 03-setup-kerberos-primary.sh
│   ├── 04-integrate-ldap-kerberos.sh
│   ├── 05-setup-apache-tls-kerberos.sh
│   ├── 06-setup-ldap-replica.sh
│   ├── 07-setup-kerberos-secondary.sh
│   ├── 08-setup-haproxy.sh
│   └── 09-setup-monitoring.sh
├── pki/
│   └── ca-commands.sh                 # referencia; el flujo real esta en scripts/01
├── ldap/
│   ├── slapd-services.conf
│   ├── syncprov-master.ldif
│   ├── syncrepl-replica.ldif
│   ├── replicator-account.ldif
│   └── kerberos-schema-import.md
├── kerberos/
│   ├── kdc.conf
│   ├── krb5.conf
│   ├── kpropd.acl
│   └── windows-client-setup.md       # krb5.ini + hosts + Firefox about:config
├── apache/
│   └── seguro.conf                   # vhost protegido con GSSAPI
├── haproxy/
│   └── haproxy.cfg
├── monitoring/
│   ├── prometheus.yml
│   ├── ldap_repl_check.sh
│   ├── node_exporter.service
│   ├── ldap-repl-check.service
│   └── ldap-repl-check.timer
└── tests/
    ├── test-ldap-replication.sh      # punto 6
    ├── test-kdc-failover.sh          # punto 7
    ├── test-loadbalancer.sh          # punto 8
    ├── test-fault-kill9.sh           # punto 9.1
    ├── test-fault-network-partition.sh  # punto 9.2
    ├── test-fault-cert-expired.sh    # punto 9.3
    └── test-fault-kdc-down.sh        # punto 9.4
```

## Requisitos

- Ubuntu 24.04 (probado en WSL2)
- OpenLDAP (slapd, ldap-utils)
- MIT Kerberos (krb5-kdc, krb5-admin-server, krb5-kpropd, krb5-user)
- OpenSSL 3.x
- Docker (para la replica LDAP y el KDC secundario)
- HAProxy 2.8+
- Apache2 + libapache2-mod-auth-gssapi
- Prometheus, node_exporter, Grafana

## Instalacion desde cero (verificacion del proyecto)

Probado en Ubuntu 24.04 (WSL2), maquina limpia con Docker disponible. Requiere `sudo`.

```bash
git clone <URL_DEL_REPO> fis-miniidm
cd fis-miniidm
make setup
```

`make setup` corre en orden los 10 scripts de `scripts/00-*.sh` a `scripts/09-*.sh`,
que reconstruyen exactamente la infraestructura descrita en el informe: CA raiz,
LDAP master, KDC primario, integracion LDAP-Kerberos, servicio web con SPNEGO, replica
LDAP en Docker, KDC secundario en Docker con propagacion kprop/kpropd, HAProxy y el
stack de monitoreo (Prometheus + node_exporter + Grafana). Toma entre 15 y 25 minutos.

El proceso pide interactivamente 4 contrasenas (admin LDAP, master key de Kerberos,
password de jperez, password de la cuenta replicator) — no hay contrasenas
hardcodeadas en el repositorio. Cada script puede tambien correrse individualmente
(`bash scripts/02-setup-ldap-master.sh`) si se necesita revisar o repetir un paso
puntual; el orden importa porque cada uno depende del anterior (ver comentarios al
inicio de cada archivo).

Al terminar:

```bash
make status          # confirma que cada servicio esta activo
make verify-all       # corre las 4 baterias de pruebas (puntos 6, 7, 8 y 9) en secuencia
```

`make verify-all` reproduce, con timestamps reales al momento de ejecutarse, todas las
pruebas descritas en el informe: replicacion LDAP, failover de Kerberos, balanceo de
carga y los 4 experimentos de inyeccion de fallos. La salida de cada prueba indica
explicitamente que se esta verificando y el resultado esperado.

Tras un reinicio de la maquina (los servicios no siempre persisten en WSL entre
reinicios), usar `make start` en vez de repetir `make setup`.

### Notas para la verificacion

- Los certificados y llaves se generan en `/etc/ssl/fis-pki/` durante `01-setup-pki.sh`;
  ninguna clave privada viaja en el repositorio.
- Grafana requiere 2 pasos manuales por su interfaz web (agregar Prometheus como data
  source y crear el dashboard); `09-setup-monitoring.sh` imprime las queries exactas de
  cada panel al finalizar.
- El SSO Kerberos desde un cliente Windows (MIT Kerberos for Windows + Firefox) requiere
  configuracion adicional del lado del cliente, documentada en
  `kerberos/windows-client-setup.md`; desde Linux, `tests/*.sh` ya lo verifican con
  `curl --negotiate` sin pasos manuales.

## Pruebas

Cada prueba corresponde a un punto del enunciado y produce timestamps en la salida:

```bash
make test-replication     # punto 6: replicacion LDAP + failover de lectura
make test-kdc-failover    # punto 7: failover del KDC (primario -> secundario)
make test-loadbalancer    # punto 8: HAProxy, stop de slapd en el master
make test-faults          # punto 9: los 4 experimentos de inyeccion de fallos
```

## Monitoreo

Prometheus: `http://localhost:9090` | Grafana: `http://localhost:3000`

Metricas expuestas:
- `up{job="haproxy"}`, `haproxy_server_status`, `haproxy_server_current_sessions` — estado y trafico de LDAP
- `node_cpu_seconds_total`, `node_memory_MemAvailable_bytes` — CPU y memoria
- `ldap_replication_lag_seconds` — retraso de replicacion (script propio, `monitoring/ldap_repl_check.sh`)

## Decisiones de diseno relevantes

- **Integracion LDAP-Kerberos**: se opto por sincronizacion de atributos (`krbPrincipalName`
  en cada entrada LDAP) en vez de migrar Kerberos a un backend LDAP (modelo FreeIPA). Esto
  hace que la autenticacion Kerberos siga funcionando aunque LDAP este caido, a costa de
  requerir sincronizacion manual entre ambas bases. Detalle en el informe.
- **Failover de Kerberos es manual**: el cliente debe tener ambos KDC listados en `krb5.conf`
  para failover automatico; no se implemento persistencia de esa configuracion en el cliente
  de pruebas. Limitacion documentada en el informe.

## Uso de ayuda externa

Este proyecto fue desarrollado con asistencia de Claude (Anthropic) como apoyo para
diagnostico de errores de configuracion (Kerberos/SPNEGO en Windows, replicacion LDAP,
propagacion de KDC), generacion de scripts de prueba y redaccion del informe. Todas las
decisiones de arquitectura, la ejecucion de las pruebas y la verificacion de resultados
fueron realizadas por el autor sobre su propio entorno WSL2 + Docker.

## Informe

Ver `docs/AnacichaD-MiniIdM.pdf`.
