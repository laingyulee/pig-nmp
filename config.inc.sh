#!/usr/bin/env bash
#
# Pig-NMP - Nginx/MySQL(MariaDB)/PHP Environment Manager
# Global Configuration
#

PIG_NMP_VERSION="1.0.0"
PIG_NMP_NAME="Pig-NMP"

PIG_NMP_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
LIB_DIR="${PIG_NMP_DIR}/lib"
MODULES_DIR="${PIG_NMP_DIR}/modules"
WIZARD_DIR="${PIG_NMP_DIR}/wizard"
TEMPLATES_DIR="${PIG_NMP_DIR}/templates"
CONF_DIR="${PIG_NMP_DIR}/conf"

INSTALL_PREFIX="/usr/local"
ETC_DIR="/etc/pig-nmp"
LOG_DIR="/var/log/pig-nmp"
RUN_DIR="/var/run/pig-nmp"
DATA_DIR="/var/lib/pig-nmp"
TMP_DIR="/tmp/pig-nmp"

NGINX_DIR="${INSTALL_PREFIX}/nginx"
NGINX_ETC_DIR="${ETC_DIR}/nginx"
NGINX_SITES_AVAILABLE="${NGINX_ETC_DIR}/sites-available"
NGINX_SITES_ENABLED="${NGINX_ETC_DIR}/sites-enabled"

PHP_BASE_DIR="${INSTALL_PREFIX}"
PHP_ETC_DIR="${ETC_DIR}/php"

MYSQL_DATA_DIR="${DATA_DIR}/mysql"
MYSQL_ETC_DIR="${ETC_DIR}/mysql"

REDIS_DIR="${INSTALL_PREFIX}/redis"
REDIS_ETC_DIR="${ETC_DIR}/redis"
REDIS_DATA_DIR="${DATA_DIR}/redis"

MEMCACHED_DIR="${INSTALL_PREFIX}/memcached"
MEMCACHED_ETC_DIR="${ETC_DIR}/memcached"

PHPMYADMIN_DIR="${INSTALL_PREFIX}/phpmyadmin"
PHPMYADMIN_ETC_DIR="${ETC_DIR}/phpmyadmin"

FTP_ETC_DIR="${ETC_DIR}/vsftpd"
FTP_USER_DIR="${ETC_DIR}/vsftpd/users"

IONCUBE_DIR="${INSTALL_PREFIX}/ioncube"

ACME_DIR="${INSTALL_PREFIX}/acme.sh"
SSL_DIR="${ETC_DIR}/ssl"

BACKUP_DIR="${DATA_DIR}/backups"

PHP_FPM_PORTS_START=9081

DOMAINS_DIR="/home/www/domains"

ensure_domains_dir() {
    if [[ ! -d "${DOMAINS_DIR}" ]]; then
        mkdir -p "${DOMAINS_DIR}"
        log_info "Created domains directory: ${DOMAINS_DIR}"
    fi
    chown -R www-data:www-data "/home/www"
    chmod 755 "/home/www"
    chmod 755 "${DOMAINS_DIR}"
}

MIRROR_CN="false"

SYSCTL_MEM=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
CPU_CORES=$(nproc 2>/dev/null || echo 1)
