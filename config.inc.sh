#!/usr/bin/env bash
#
# Pig-NMP - Global Configuration
#

PIG_NMP_VERSION="1.1.0"
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

SSL_DIR="${ETC_DIR}/ssl"
BACKUP_DIR="${DATA_DIR}/backups"

PHP_FPM_PORTS_START=9081
DOMAINS_DIR="/home/www"

MIRROR_CN="false"

SYSCTL_MEM=$(grep MemTotal /proc/meminfo 2>/dev/null | awk '{print $2}')
CPU_CORES=$(nproc 2>/dev/null || echo 1)
