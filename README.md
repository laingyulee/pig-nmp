<p align="center">
  <img src="https://img.shields.io/badge/Platform-Debian%2FUbuntu-green" alt="Platform">
  <img src="https://img.shields.io/badge/License-MIT-blue" alt="License">
  <img src="https://img.shields.io/badge/Shell-Bash-1DA1F2" alt="Shell">
</p>

# Pig-NMP

**Nginx + MySQL/MariaDB + PHP** — A one-stop server environment manager for Debian/Ubuntu. All components are downloaded from official sources. Supports multi-version PHP co-existence, virtual host wizard, SSL certificate management, and more.

---

## Table of Contents

- [Features](#features)
- [System Requirements](#system-requirements)
- [Quick Start](#quick-start)
- [Directory Structure](#directory-structure)
- [Usage Guide](#usage-guide)
  - [Interactive Menu](#interactive-menu)
  - [Command Line Mode](#command-line-mode)
  - [Nginx Management](#nginx-management)
  - [PHP Multi-Version Management](#php-multi-version-management)
  - [MySQL/MariaDB Management](#mysqlmariadb-management)
  - [Redis Management](#redis-management)
  - [Memcached Management](#memcached-management)
  - [PHP Extension Management](#php-extension-management)
  - [ionCube Loader](#ioncube-loader)
  - [phpMyAdmin Management](#phpmyadmin-management)
  - [FTP Server Management](#ftp-server-management)
  - [Firewall Management](#firewall-management)
  - [Virtual Host Wizard](#virtual-host-wizard)
  - [SSL Certificate Wizard](#ssl-certificate-wizard)
  - [System Manager Panel](#system-manager-panel)
- [Configuration File Paths](#configuration-file-paths)
- [Port Assignment](#port-assignment)
- [Mirror Acceleration](#mirror-acceleration)
- [FAQ](#faq)
- [Uninstall](#uninstall)

---

## Features

| Component | Install Method | Versions | Management |
|------|----------|----------|----------|
| **Nginx** | Official APT / Source | stable / mainline | Start, stop, reload, config test |
| **PHP** | Source compile | 8.1 / 8.2 / 8.3 / 8.4 | Multi-version, default version, FPM tuning |
| **MySQL** | Official APT | 8.0 / 8.4 / 9.1 | Secure init, DB/user management |
| **MariaDB** | Official APT | 10.11 / 11.4 / 11.6 | Secure init, DB/user management |
| **Redis** | Source compile | 7.4+ | Password, persistence config |
| **Memcached** | Source compile | 1.6+ | Memory/connection config |
| **phpMyAdmin** | Official download | 5.2+ | Subdomain/path access, security hardening |
| **FTP (vsftpd)** | APT / Source | 3.0+ | Virtual users, passive mode, SSL/TLS |
| **ionCube** | Official download | Matches PHP | Per-version install |
| **UFW Firewall** | APT | - | Three security presets, auto-config |

**Wizard features:**

- Virtual host creation wizard (WordPress / Laravel / ThinkPHP / Typecho / CodeIgniter / Drupal rewrite rules built-in)
- SSL certificate wizard (Let's Encrypt auto-issue / self-signed)
- System manager panel (status monitor, quick install, config backup)

---

## System Requirements

### Supported OS

| OS | Version | Codename | Status |
|----------|------|------|------|
| **Debian** | 12 | Bookworm | ✅ Fully tested |
| **Debian** | 11 | Bullseye | ✅ Compatible |
| **Ubuntu** | 24.04 LTS | Noble Numbat | ✅ Fully tested |
| **Ubuntu** | 22.04 LTS | Jammy Jellyfish | ✅ Fully tested |
| **Ubuntu** | 20.04 LTS | Focal Fossa | ⚠️ Basic compatibility (some new components may need manual tweaks) |
| ~~Debian 10~~ | ~~10~~ | ~~Buster~~ | ❌ End of life |
| ~~Ubuntu 18.04~~ | ~~18.04~~ | ~~Bionic~~ | ❌ End of life |

> The script auto-detects the OS and codename via `/etc/os-release` and `/etc/debian_version` to configure correct APT sources. Only **x86_64 (amd64)** architecture is supported.

### Hardware Requirements

| Item | Minimum | Recommended |
|------|----------|----------|
| Architecture | x86_64 (amd64) | x86_64 |
| Memory | 1 GB | 2 GB+ |
| Disk | 10 GB | 20 GB+ |
| Privilege | root | root |
| Network | Internet access required | - |

> **Note:** PHP source compilation requires at least 1.5 GB of available memory. The script will auto-create a 2 GB swap partition if memory is insufficient.

### Software Dependencies

The script automatically installs these system dependencies:

| Dependency | Purpose |
|------|------|
| `build-essential` | C/C++ build toolchain |
| `libssl-dev` | OpenSSL dev library (Nginx/PHP) |
| `libpcre2-dev` / `libpcre3-dev` | Regex library (Nginx) |
| `libmagickwand-dev` | ImageMagick dev library (PHP imagick) |
| `libsqlite3-dev` | SQLite dev library (PHP) |
| `curl` / `wget` | Download tools |
| `gnupg` | APT repo signature verification |

---

## Quick Start

### 1. Download

```bash
# Option A: git clone
git clone https://github.com/laingyulee/pig-nmp.git
cd pig-nmp

# Option B: Download and upload to your server
```

### 2. Run the main script

```bash
chmod +x pig-nmp.sh
sudo bash pig-nmp.sh
```

The first run displays the interactive main menu:

```
  ___ ___ ___     _       _                  _   _
 | _ \_ _/ __|   /_\ _  _| |_ ___ _ __  __ _| |_(_)___ _ _
 |  _/| | (_ |  / _ \ || |  _/ _ \ '  \/ _` |  _| / _ \ ' \
 |_| |___\___| /_/ \_\_,_|\__\___/_|_|_\__,_|\__|_\___/_||_|

  Nginx + MySQL/MariaDB + PHP Environment Manager
  Version 1.0.0

  Component Status:
  ● Nginx 1.30.2
  ● PHP 8.3
  ● MARIADB
  ● Redis 8.8.0
  ○ Memcached (not installed)
  ○ phpMyAdmin (not installed)
  ○ FTP (not installed)

========================================================================================

  1)  Install/Update Components
  2)  Manage Virtual Hosts
  3)  Configure SSL Certificates
  4)  PHP Version & Extension Management
  5)  FTP Server Management
  6)  Firewall (UFW) Management
  7)  System Status & Manager
  8)  Uninstall Components

  0)  Exit

Enter choice:
```

### 3. One-click NMP Install

Select menu `1` → `9` (Quick Install), or run directly from the command line:

```bash
sudo bash pig-nmp.sh install
```

This will sequentially install Nginx + PHP + MySQL/MariaDB.

---

## Directory Structure

```
Pig-NMP/
├── pig-nmp.sh                  # Main entry script
├── config.inc.sh               # Global configuration
├── lib/                        # Core utilities
│   ├── common.sh               # Common functions (logging, input, template rendering)
│   ├── color.sh                # Terminal color output
│   ├── download.sh             # Download / extract / PECL install
│   └── os.sh                   # OS detection, deps, system optimization
├── modules/                    # Feature modules
│   ├── nginx.sh                # Nginx install & management
│   ├── php.sh                  # PHP multi-version install & management
│   ├── mysql.sh                # MySQL/MariaDB install & management
│   ├── redis.sh                # Redis install & management
│   ├── memcached.sh            # Memcached install & management
│   ├── php-ext.sh              # PHP extension management
│   ├── phpmyadmin.sh           # phpMyAdmin install & management
│   ├── ftp.sh                  # FTP (vsftpd) install & management
│   ├── firewall.sh             # UFW firewall management
│   └── ioncube.sh              # ionCube Loader management
├── wizard/                     # Configuration wizards
│   ├── vhost.sh                # Virtual host wizard
│   ├── ssl.sh                  # SSL certificate wizard
│   └── manager.sh              # System manager panel
├── templates/                  # Config file templates
│   ├── nginx/                  # Nginx config templates
│   ├── php/                    # PHP/FPM config templates
│   ├── mysql/                  # MySQL config templates
│   ├── ftp/                    # vsftpd config templates
│   └── systemd/                # systemd service templates
└── conf/                       # Version & mirror config
    ├── versions.conf           # Component versions
    └── mirrors.conf            # China mirror configuration
```

---

## Usage Guide

### Interactive Menu

Run `sudo bash pig-nmp.sh` to enter the interactive menu. Select functions by number.

### Command Line Mode

Supports direct command-line arguments for scripted automation:

```bash
sudo bash pig-nmp.sh nginx      # Nginx management menu
sudo bash pig-nmp.sh php        # PHP management menu
sudo bash pig-nmp.sh mysql      # MySQL/MariaDB management menu
sudo bash pig-nmp.sh redis      # Redis management menu
sudo bash pig-nmp.sh memcached  # Memcached management menu
sudo bash pig-nmp.sh pma        # phpMyAdmin management menu
sudo bash pig-nmp.sh ftp        # FTP management menu
sudo bash pig-nmp.sh firewall   # Firewall management menu
sudo bash pig-nmp.sh ioncube    # ionCube management menu
sudo bash pig-nmp.sh vhost      # Virtual host management menu
sudo bash pig-nmp.sh ssl        # SSL certificate management menu
sudo bash pig-nmp.sh status     # Show system status
sudo bash pig-nmp.sh install    # Quick install NMP
sudo bash pig-nmp.sh help       # Show help
```

---

### Nginx Management

#### Installation

Select menu `1` → `1`, two installation methods are available:

**Method 1: Official APT repository (recommended)**

- Automatically adds the nginx.org official APT repository
- Choose between stable or mainline branch
- Fast installation, updates via `apt upgrade`

**Method 2: Source compilation**

- Download and compile from nginx.org
- Customizable compile modules (http_image_filter, http_geoip, http_dav, mail, etc.)
- Default: SSL, HTTP/2, HTTP/3, RealIP, Gzip, Stub Status, Stream, etc.

#### Management

```
Nginx Management
  1) Install Nginx
  2) Uninstall Nginx
  3) Start/Stop/Restart
  4) Reload Configuration
  5) Test Configuration
  6) Status
  0) Back
```

---

### PHP Multi-Version Management

#### Installing PHP

Select menu `1` → `2`, downloads and compiles from php.net.

**Supported versions:** 8.1 / 8.2 / 8.3 / 8.4

**Default compiled extensions:**
pdo_mysql, mysqli, mbstring, openssl, curl, json, xml, zip, bcmath, opcache, pcntl, posix, tokenizer, ctype, fileinfo, session, filter, hash, gd, intl, soap, sockets, xsl, readline, ftp, bz2, gmp, exif, gettext, sodium, argon2, ldap

> PHP compilation typically takes 10-20 minutes depending on server performance.

**Multi-version co-existence:**

Each PHP version is installed to its own directory:

```
/usr/local/php8.1/    # PHP 8.1
/usr/local/php8.2/    # PHP 8.2
/usr/local/php8.3/    # PHP 8.3
/usr/local/php8.4/    # PHP 8.4
```

Each version runs an independent php-fpm process listening on different ports or Unix sockets:

```
PHP 8.1 → /var/run/pig-nmp/php-fpm/php8.1.sock  (port 9081)
PHP 8.2 → /var/run/pig-nmp/php-fpm/php8.2.sock  (port 9082)
PHP 8.3 → /var/run/pig-nmp/php-fpm/php8.3.sock  (port 9083)
PHP 8.4 → /var/run/pig-nmp/php-fpm/php8.4.sock  (port 9084)
```

#### Setting the Default Version

```bash
# Interactive
sudo bash pig-nmp.sh php → Select "Set default PHP version"
```

After setting, the `php`, `phpize`, `php-config`, `pear`, `pecl` commands will point to the default version.

#### php-fpm Tuning

Process management can be tuned per version:

- **pm** = dynamic (recommended) / static / ondemand
- **pm.max_children** = max child processes
- **pm.start_servers** = processes on startup
- **pm.min_spare_servers** = minimum idle processes
- **pm.max_spare_servers** = maximum idle processes

#### Assigning PHP Version to Virtual Hosts

When creating a virtual host, you will be prompted to select a PHP version. The `fastcgi_pass` in the Nginx config will point to the corresponding version's socket.

---

### MySQL/MariaDB Management

#### Installation

Select menu `1` → `3`, then choose MySQL or MariaDB:

**MySQL versions:** 8.0 / 8.4 / 9.1
**MariaDB versions:** 10.11 / 11.4 / 11.6

Installation process:
1. Add official APT repository
2. Install via APT
3. Run secure initialization wizard

#### Secure Initialization

Automatically runs after installation:

- Set root password (can be auto-generated)
- Remove anonymous users
- Disallow remote root login
- Remove test database
- Root password saved in `/etc/pig-nmp/mysql/.root_password` (permissions 600)

#### Create Database and User

```
MySQL/MariaDB Management → 4) Create database and user
```

Interactive input:
- Database name
- Username (default: same as database name)
- Password (leave blank to auto-generate)

---

### Redis Management

Downloaded from redis.io and compiled from source.

**Configuration:**
- Listen address: 127.0.0.1:6379
- Persistence: RDB + AOF (enabled by default)
- Max memory: 20% of system memory
- Eviction policy: allkeys-lru
- Password: optional

```bash
# Set Redis password
sudo bash pig-nmp.sh redis → 4) Set password
```

---

### Memcached Management

Downloaded from memcached.org and compiled from source.

**Configuration:**
- Listen address: 127.0.0.1:11211
- Max memory: 10% of system memory
- Max connections: 1024

---

### PHP Extension Management

Select menu `4` → `2` (PHP Extension Management).

**Supported extensions (18+):**

| Extension | Description | System Deps |
|-----------|------|----------|
| imagick | Image processing with ImageMagick | libmagickwand-dev, imagemagick |
| redis | Redis client | - |
| memcached | Memcached client | libmemcached-dev |
| gd | GD image processing | libgd-dev |
| intl | Internationalization | libicu-dev |
| mongodb | MongoDB client | libssl-dev |
| swoole | Async coroutine framework | libssl-dev |
| yaml | YAML parsing | libyaml-dev |
| xdebug | Debugging / profiling | - |
| grpc | gRPC framework | - |
| protobuf | Protocol Buffers | - |
| ssh2 | SSH2 | libssh2-1-dev |
| rdkafka | Kafka client | librdkafka-dev |
| amqp | AMQP protocol | librabbitmq-dev |
| pcov | Code coverage | - |
| excimer | Profiling | - |
| mcrypt | Encryption (deprecated) | libmcrypt-dev |
| opcache | OPcache (usually built-in) | - |

**Installing extensions:**

```bash
# Interactive install
sudo bash pig-nmp.sh php-ext
# → Select PHP version → Enter extension name
```

**Batch install common extensions:**

Select `5) Batch install common extensions` to auto-install imagick, redis, memcached, mongodb, swoole, yaml.

---

### ionCube Loader

ionCube is a runtime loader for encrypted PHP code, commonly used to run encrypted commercial PHP software.

**Installation process:**

1. Download Linux x86_64 Loaders from ioncube.com
2. Extract to `/usr/local/ioncube/`
3. Auto-match installed PHP versions
4. Copy the matching `ioncube_loader_lin_X.Y.so` to each PHP extension directory
5. Prepend `zend_extension` line to `php.ini`
6. Restart php-fpm and verify

```bash
# Interactive install
sudo bash pig-nmp.sh ioncube → 1) Install ionCube

# Verify
/usr/local/php8.3/bin/php -v
# Output should include: with the ionCube PHP Loader
```

> **Note:** ionCube must be loaded as a `zend_extension` and must appear before any other zend extensions. Cannot be used simultaneously with SourceGuardian or other encryption extensions.

---

### phpMyAdmin Management

#### Installation

Prerequisites: Nginx + at least one PHP version + MySQL/MariaDB must be installed.

Installation process:
1. Download phpMyAdmin to `/usr/local/phpmyadmin/`
2. Generate config file (with random Blowfish Secret)
3. Choose access method:
   - **Subdomain access:** e.g. `pma.example.com` (creates a separate virtual host)
   - **URL path access:** e.g. `example.com/pma` (adds a location block to existing vhost)
4. Security configuration (optional):
   - IP whitelist
   - HTTP Basic Auth

#### Security Hardening

**Set IP whitelist:**
```
phpMyAdmin Management → 4) Configure security → Set IP whitelist
# Enter allowed IP or CIDR (e.g. 192.168.1.0/24)
```

**Set HTTP Basic Auth:**
```
phpMyAdmin Management → 4) Configure security → Set HTTP Basic Auth
# Enter username and password
```

**Update phpMyAdmin:**
```
phpMyAdmin Management → 2) Update phpMyAdmin
# Enter new version number, auto-backup, update, and restore config
```

---

### FTP Server Management

#### Installing vsftpd

Supports APT install or source compilation.

Post-install interactive configuration:
- Passive mode port range (default 40000-40100)
- FTP over TLS/SSL (optional)

#### User Management

**Virtual users (recommended):**

Virtual users authenticate via PAM without creating system users. Each user can have an independent home directory.

```bash
FTP Server Management → 3) Add FTP user
# Select "Virtual user"
# Enter username, password, home directory
```

**System users:**

Create Linux system users with `/usr/sbin/nologin` as the login shell.

#### Passive Mode Configuration

FTP passive mode requires opening a port range and configuring the server's public IP:

```bash
FTP Server Management → 7) Configure passive mode
# Enter port range (default 40000-40100)
# Enter server public IP
```

> Ensure the firewall has opened the passive port range.

#### SSL/TLS Configuration

```bash
FTP Server Management → 8) Configure SSL/TLS
# Auto-generates a self-signed certificate
# Or specify an existing certificate path
```

---

### Firewall Management

UFW (Uncomplicated Firewall) based firewall management.

#### Security Presets

| Port | Development | Production | Strict |
|------|----------|----------|--------|
| 22 (SSH) | Open | Open | IP-restricted |
| 80 (HTTP) | Open | Open | Open |
| 443 (HTTPS) | Open | Open | Open |
| 21 (FTP) | Open | Closed | Closed |
| 3306 (MySQL) | Open | Closed | Closed |
| 6379 (Redis) | Open | Closed | Closed |
| 11211 (Memcached) | Open | Closed | Closed |
| 40000-40100 (FTP passive) | Open | Open | Closed |

```bash
# Apply security preset
sudo bash pig-nmp.sh firewall → 3) Apply security profile
```

#### Auto-Configuration

```bash
sudo bash pig-nmp.sh firewall → 6) Auto-configure
```

Auto-detects installed services and configures rules:
- Nginx → Open 80/443
- FTP → Open 21 + passive ports
- MySQL → Block 3306 (SSH tunnel recommended)
- Redis → Block 6379 (local only)
- Memcached → Block 11211 (local only)

---

### Virtual Host Wizard

#### Creating a Virtual Host

```
Virtual Host Management → 1) Create virtual host
```

The wizard will ask:

1. **Domain:** e.g. `example.com`
2. **Document root:** default `/home/www/domains/example.com`
3. **PHP version:** select an installed PHP version (determines fastcgi_pass target)
4. **Enable SSL:** yes/no
5. **Rewrite rules:** choose from supported frameworks

**Supported rewrite rules:**

| Framework | Rule |
|------|------|
| WordPress | `try_files $uri $uri/ /index.php?$args;` |
| Laravel | `try_files $uri $uri/ /index.php?$query_string;` |
| ThinkPHP | `rewrite ^(.*)$ /index.php?s=$1 last;` |
| Typecho | `rewrite ^(.*)$ /index.php$1 last;` |
| CodeIgniter | `try_files $uri $uri/ /index.php/$uri?$query_string;` |
| Drupal | `try_files $uri /index.php?$query_string;` |

After creation, Nginx config files are generated at:

```
/etc/pig-nmp/nginx/sites-available/example.com.conf
/etc/pig-nmp/nginx/sites-enabled/example.com.conf  (symlink)
```

#### Enable / Disable Virtual Host

```
Enable: Virtual Host Management → 4) Enable virtual host
Disable: Virtual Host Management → 5) Disable virtual host
```

Implemented by creating/removing symlinks in `sites-enabled` without modifying config files.

#### Deleting a Virtual Host

```
Virtual Host Management → 2) Delete virtual host
```

Optionally delete the document root as well.

---

### SSL Certificate Wizard

#### Let's Encrypt Certificate

```
SSL Certificate Management → 1) Issue Let's Encrypt certificate
```

Three verification methods are supported:

1. **HTTP (webroot)** — Most common, auto-places verification file in the site root
2. **DNS (manual)** — Manually add DNS TXT record
3. **DNS (Cloudflare API)** — Auto-add DNS records via Cloudflare API

Installs acme.sh and auto-configures certificate renewal cron job.

#### Self-Signed Certificate

```
SSL Certificate Management → 2) Generate self-signed certificate
```

For testing environments. Browsers will show a security warning.

#### Certificate Renewal

```
SSL Certificate Management → 3) Renew certificate
# Renew for a specific domain or all certificates
```

acme.sh auto-renews by default; this is for manual triggering.

#### View Certificate Info

```
SSL Certificate Management → 6) Show certificate info
# Shows validity, issuer, etc.
```

---

### System Manager Panel

```
System Manager
  1) System status         — OS, memory, disk, load info
  2) Services status       — All component running status
  3) Port status           — Port usage
  4) Quick install NMP     — One-click Nginx + PHP + MySQL
  5) Backup configuration  — Backup all config files
  6) System optimization   — Kernel parameters, file descriptor tuning
```

---

## Configuration File Paths

All configuration files are stored under `/etc/pig-nmp/`:

| Component | Config Path |
|------|------------|
| Nginx main config | `/etc/pig-nmp/nginx/nginx.conf` |
| Sites available | `/etc/pig-nmp/nginx/sites-available/` |
| Sites enabled | `/etc/pig-nmp/nginx/sites-enabled/` |
| Nginx extra config | `/etc/pig-nmp/nginx/conf.d/` |
| PHP config | `/etc/pig-nmp/php/{version}/php.ini` |
| php-fpm config | `/etc/pig-nmp/php/{version}/php-fpm.conf` |
| php-fpm Pool | `/etc/pig-nmp/php/{version}/fpm/pool.d/www.conf` |
| MySQL/MariaDB config | `/etc/pig-nmp/mysql/my.cnf` |
| MySQL root password | `/etc/pig-nmp/mysql/.root_password` |
| Redis config | `/etc/pig-nmp/redis/redis.conf` |
| vsftpd config | `/etc/pig-nmp/vsftpd/vsftpd.conf` |
| FTP virtual users | `/etc/pig-nmp/vsftpd/users/` |
| SSL certificates | `/etc/pig-nmp/ssl/{domain}/` |

**Installation paths:**

| Component | Path |
|------|----------|
| Nginx (source) | `/usr/local/nginx/` |
| PHP versions | `/usr/local/php{version}/` |
| Redis | `/usr/local/redis/` |
| Memcached | `/usr/local/memcached/` |
| ionCube Loaders | `/usr/local/ioncube/` |
| phpMyAdmin | `/usr/local/phpmyadmin/` |
| acme.sh | `~/.acme.sh/` |

**Log paths:**

| Log | Path |
|------|------|
| Nginx access log | `/var/log/pig-nmp/nginx/access.log` |
| Nginx error log | `/var/log/pig-nmp/nginx/error.log` |
| Site access log | `/var/log/pig-nmp/nginx/{domain}.access.log` |
| PHP error log | `/var/log/pig-nmp/php/php-errors.log` |
| php-fpm error log | `/var/log/pig-nmp/php-fpm/` |
| MySQL slow query log | `/var/log/pig-nmp/mysql/slow.log` |
| Redis log | `/var/log/pig-nmp/redis/redis.log` |
| vsftpd log | `/var/log/pig-nmp/vsftpd/vsftpd.log` |
| Pig-NMP error log | `/var/log/pig-nmp/error.log` |

---

## Port Assignment

| Port | Service | Description |
|------|------|------|
| 22 | SSH | Remote management |
| 80 | Nginx (HTTP) | Website access |
| 443 | Nginx (HTTPS) | Secure website access |
| 21 | vsftpd (FTP) | File transfer |
| 3306 | MySQL/MariaDB | Database (local only recommended) |
| 6379 | Redis | Cache (local only recommended) |
| 11211 | Memcached | Cache (local only recommended) |
| 9081 | PHP-FPM 8.1 | Fallback port (Unix socket by default) |
| 9082 | PHP-FPM 8.2 | Fallback port |
| 9083 | PHP-FPM 8.3 | Fallback port |
| 9084 | PHP-FPM 8.4 | Fallback port |
| 40000-40100 | FTP passive mode | Customizable range |

---

## Mirror Acceleration

If your server is located in Mainland China, enable mirror acceleration for downloads.

Edit `config.inc.sh`:

```bash
# Set MIRROR_CN to "true"
MIRROR_CN="true"
```

Supported mirrors:
- PHP → sohu mirror
- Nginx → huawei mirror
- Redis → huawei mirror
- phpMyAdmin → huawei mirror

Falls back to official sources if mirror download fails.

---

## FAQ

### Q: PHP compilation failed?

Check the compilation logs:

```bash
cat /var/log/pig-nmp/php-{version}-configure.log
cat /var/log/pig-nmp/php-{version}-make.log
```

Common causes:
- Missing system dependencies → run system optimization or manually install `build-essential`, etc.
- Insufficient memory → add swap (the script auto-adds swap for systems with less than 2 GB RAM)

### Q: How to run multiple PHP versions on the same server?

Each virtual host's Nginx `fastcgi_pass` points to the corresponding PHP version's socket:

```nginx
# Site A uses PHP 8.2
fastcgi_pass unix:/var/run/pig-nmp/php-fpm/php8.2.sock;

# Site B uses PHP 8.3
fastcgi_pass unix:/var/run/pig-nmp/php-fpm/php8.3.sock;
```

Select the PHP version during the virtual host wizard to auto-configure.

### Q: How to connect to MySQL remotely?

**Opening port 3306 directly is not recommended.** Use an SSH tunnel instead:

```bash
ssh -L 3306:127.0.0.1:3306 user@your-server
# Then connect to 127.0.0.1:3306 locally
```

If remote access is truly required, open port 3306 in the firewall and grant remote user permissions in MySQL.

### Q: Website errors after installing ionCube?

Ensure the `zend_extension` line for ionCube appears before all other zend extensions in `php.ini`. Check:

```bash
/usr/local/php8.3/bin/php -v
# If errors, check zend_extension order in php.ini
```

### Q: Let's Encrypt certificate issuance failed?

- Ensure the domain resolves to your server IP
- Ensure port 80 is accessible from the internet
- Check Nginx config: `nginx -t`
- If using DNS verification, ensure the TXT record has propagated

### Q: FTP connection timeout?

- Check that the firewall has opened ports 21 and the passive port range
- Check `pasv_address` in passive mode config — must be the server's public IP
- If using Alibaba Cloud / Tencent Cloud, open the ports in the security group as well

### Q: How to modify PHP config (upload_max_filesize, etc.)?

Edit the `php.ini` for the corresponding version:

```bash
vi /etc/pig-nmp/php/8.3/php.ini
# Modify upload_max_filesize, memory_limit, etc.

# Then restart php-fpm
systemctl restart php8.3-fpm
```

---

## Uninstall

Uninstall components one by one via the interactive menu `8) Uninstall Components`, or remove everything manually:

```bash
# Stop all services
systemctl stop nginx php*-fpm mysql redis memcached vsftpd 2>/dev/null

# Remove installation files
rm -rf /usr/local/nginx /usr/local/php* /usr/local/redis /usr/local/memcached
rm -rf /usr/local/phpmyadmin /usr/local/ioncube

# Remove config files
rm -rf /etc/pig-nmp

# Remove logs
rm -rf /var/log/pig-nmp

# Remove data (caution!)
rm -rf /var/lib/pig-nmp

# Remove systemd services
rm -f /etc/systemd/system/nginx.service
rm -f /etc/systemd/system/php*-fpm.service
rm -f /etc/systemd/system/redis.service
rm -f /etc/systemd/system/memcached.service
rm -f /etc/systemd/system/vsftpd.service
systemctl daemon-reload

# If installed via APT
apt remove --purge nginx mysql-server mariadb-server vsftpd ufw -y
```

---

## License

[Apache-2.0 license](https://github.com/laingyulee/pig-nmp#Apache-2.0-1-ov-file)

---

<!-- ======================================================================== -->
<!-- 中文版本 / Chinese Version                                                  -->
<!-- ======================================================================== -->

<div align="center">

---

# 🐷 Pig-NMP 中文说明

---

</div>

**Nginx + MySQL/MariaDB + PHP** 一站式服务器环境管理工具，专为 Debian/Ubuntu 设计。全部组件从官方源下载，支持多版本 PHP 共存、虚拟主机向导、SSL 证书管理等功能。

---

## 目录

- [功能特性](#功能特性)
- [系统要求](#系统要求)
- [快速开始](#快速开始)
- [目录结构](#目录结构)
- [使用指南](#使用指南)
  - [交互式菜单](#交互式菜单)
  - [命令行模式](#命令行模式)
  - [Nginx 管理](#nginx-管理)
  - [PHP 多版本管理](#php-多版本管理)
  - [MySQL/MariaDB 管理](#mysqlmariadb-管理)
  - [Redis 管理](#redis-管理)
  - [Memcached 管理](#memcached-管理)
  - [PHP 扩展管理](#php-扩展管理)
  - [ionCube Loader](#ioncube-loader)
  - [phpMyAdmin 管理](#phpmyadmin-管理)
  - [FTP 服务器管理](#ftp-服务器管理)
  - [防火墙管理](#防火墙管理)
  - [虚拟主机向导](#虚拟主机向导)
  - [SSL 证书向导](#ssl-证书向导)
  - [系统管理面板](#系统管理面板)
- [配置文件路径](#配置文件路径)
- [端口分配](#端口分配)
- [镜像加速](#镜像加速)
- [常见问题](#常见问题)
- [卸载](#卸载)

---

## 功能特性

| 组件 | 安装方式 | 版本支持 | 管理功能 |
|------|----------|----------|----------|
| **Nginx** | 官方APT源 / 源码编译 | stable / mainline | 启停、重载、配置检测 |
| **PHP** | 源码编译 | 8.1 / 8.2 / 8.3 / 8.4 | 多版本共存、切换默认版本、FPM调优 |
| **MySQL** | 官方APT源 | 8.0 / 8.4 / 9.1 | 安全初始化、数据库/用户管理 |
| **MariaDB** | 官方APT源 | 10.11 / 11.4 / 11.6 | 安全初始化、数据库/用户管理 |
| **Redis** | 源码编译 | 7.4+ | 密码设置、持久化配置 |
| **Memcached** | 源码编译 | 1.6+ | 内存/连接数配置 |
| **phpMyAdmin** | 官方下载 | 5.2+ | 子域名/路径访问、安全加固 |
| **FTP (vsftpd)** | APT / 源码编译 | 3.0+ | 虚拟用户、被动模式、SSL/TLS |
| **ionCube** | 官方下载 | 匹配PHP版本 | 多版本PHP分别安装 |
| **UFW 防火墙** | APT | - | 三种安全预设、自动配置 |

**向导功能：**

- 虚拟主机创建向导（含 WordPress / Laravel / ThinkPHP / Typecho / CodeIgniter / Drupal 伪静态规则）
- SSL 证书向导（Let's Encrypt 自动申请 / 自签名证书）
- 系统管理面板（状态监控、快速安装、配置备份）

---

## 系统要求

### 适用的操作系统

| 操作系统 | 版本 | 代号 | 状态 |
|----------|------|------|------|
| **Debian** | 12 | Bookworm | ✅ 完全测试 |
| **Debian** | 11 | Bullseye | ✅ 兼容 |
| **Ubuntu** | 24.04 LTS | Noble Numbat | ✅ 完全测试 |
| **Ubuntu** | 22.04 LTS | Jammy Jellyfish | ✅ 完全测试 |
| **Ubuntu** | 20.04 LTS | Focal Fossa | ⚠️ 基本兼容（部分新版组件可能需手动调整） |
| ~~Debian 10~~ | ~~10~~ | ~~Buster~~ | ❌ 已停止支持 |
| ~~Ubuntu 18.04~~ | ~~18.04~~ | ~~Bionic~~ | ❌ 已停止支持 |

> 脚本通过检测 `/etc/os-release` 和 `/etc/debian_version` 自动识别操作系统及版本代号，用于配置正确的 APT 源。仅支持 **x86_64 (amd64)** 架构。

### 硬件要求

| 项目 | 最低要求 | 推荐配置 |
|------|----------|----------|
| 架构 | x86_64 (amd64) | x86_64 |
| 内存 | 1 GB | 2 GB+ |
| 磁盘 | 10 GB | 20 GB+ |
| 权限 | root | root |
| 网络 | 需要访问外网下载组件 | - |

> **编译提示：** PHP 源码编译至少需要 1.5 GB 可用内存，内存不足时脚本会自动创建 2GB swap 分区。

### 软件依赖

脚本会自动安装以下系统依赖（无需手动操作）：

| 依赖 | 用途 |
|------|------|
| `build-essential` | C/C++ 编译工具链 |
| `libssl-dev` | OpenSSL 开发库（Nginx/PHP） |
| `libpcre2-dev` / `libpcre3-dev` | 正则库（Nginx） |
| `libmagickwand-dev` | ImageMagick 开发库（PHP imagick 扩展） |
| `libsqlite3-dev` | SQLite 开发库（PHP） |
| `curl` / `wget` | 下载工具 |
| `gnupg` | APT 仓库签名验证 |

---

## 快速开始

### 1. 下载项目

```bash
# 方式一：git clone
git clone https://github.com/laingyulee/pig-nmp.git
cd pig-nmp

# 方式二：直接下载并上传到服务器
```

### 2. 运行主脚本

```bash
chmod +x pig-nmp.sh
sudo bash pig-nmp.sh
```

首次运行将显示交互式主菜单：

```
  ___ ___ ___     _       _                  _   _
 | _ \_ _/ __|   /_\ _  _| |_ ___ _ __  __ _| |_(_)___ _ _
 |  _/| | (_ |  / _ \ || |  _/ _ \ '  \/ _` |  _| / _ \ ' \
 |_| |___\___| /_/ \_\_,_|\__\___/_|_|_\__,_|\__|_\___/_||_|

  Nginx + MySQL/MariaDB + PHP Environment Manager
  Version 1.0.0

  Component Status:
  ● Nginx 1.30.2
  ● PHP 8.3
  ● MARIADB
  ● Redis 8.8.0
  ○ Memcached (not installed)
  ○ phpMyAdmin (not installed)
  ○ FTP (not installed)

========================================================================================

  1)  Install/Update Components
  2)  Manage Virtual Hosts
  3)  Configure SSL Certificates
  4)  PHP Version & Extension Management
  5)  FTP Server Management
  6)  Firewall (UFW) Management
  7)  System Status & Manager
  8)  Uninstall Components

  0)  Exit

Enter choice:
```

### 3. 一键安装 NMP 环境

选择菜单 `1` → `9` (Quick Install)，或在命令行直接运行：

```bash
sudo bash pig-nmp.sh install
```

将自动依次安装 Nginx + PHP + MySQL/MariaDB。

---

## 目录结构

```
Pig-NMP/
├── pig-nmp.sh                  # 主入口脚本
├── config.inc.sh               # 全局配置变量
├── lib/                        # 基础工具库
│   ├── common.sh               # 通用函数（日志、输入、模板渲染等）
│   ├── color.sh                # 终端彩色输出
│   ├── download.sh             # 下载/解压/PECL安装
│   └── os.sh                   # OS检测、依赖安装、系统优化
├── modules/                    # 功能模块
│   ├── nginx.sh                # Nginx 安装与管理
│   ├── php.sh                  # PHP 多版本安装与管理
│   ├── mysql.sh                # MySQL/MariaDB 安装与管理
│   ├── redis.sh                # Redis 安装与管理
│   ├── memcached.sh            # Memcached 安装与管理
│   ├── php-ext.sh              # PHP 扩展管理
│   ├── phpmyadmin.sh           # phpMyAdmin 安装与管理
│   ├── ftp.sh                  # FTP(vsftpd)安装与管理
│   ├── firewall.sh             # UFW 防火墙管理
│   └── ioncube.sh              # ionCube Loader 管理
├── wizard/                     # 配置向导
│   ├── vhost.sh                # 虚拟主机配置向导
│   ├── ssl.sh                  # SSL 证书配置向导
│   └── manager.sh              # 系统管理面板
├── templates/                  # 配置文件模板
│   ├── nginx/                  # Nginx 配置模板
│   ├── php/                    # PHP/FPM 配置模板
│   ├── mysql/                  # MySQL 配置模板
│   ├── ftp/                    # vsftpd 配置模板
│   └── systemd/                # systemd 服务模板
└── conf/                       # 版本与镜像配置
    ├── versions.conf           # 组件版本号
    └── mirrors.conf            # 国内镜像源配置
```

---

## 使用指南

### 交互式菜单

运行 `sudo bash pig-nmp.sh` 进入交互式菜单，通过数字选择对应功能。

### 命令行模式

支持直接通过命令行参数进入特定功能模块，适合脚本化调用：

```bash
sudo bash pig-nmp.sh nginx      # Nginx 管理菜单
sudo bash pig-nmp.sh php        # PHP 管理菜单
sudo bash pig-nmp.sh mysql      # MySQL/MariaDB 管理菜单
sudo bash pig-nmp.sh redis      # Redis 管理菜单
sudo bash pig-nmp.sh memcached  # Memcached 管理菜单
sudo bash pig-nmp.sh pma        # phpMyAdmin 管理菜单
sudo bash pig-nmp.sh ftp        # FTP 管理菜单
sudo bash pig-nmp.sh firewall   # 防火墙管理菜单
sudo bash pig-nmp.sh ioncube    # ionCube 管理菜单
sudo bash pig-nmp.sh vhost      # 虚拟主机管理菜单
sudo bash pig-nmp.sh ssl        # SSL 证书管理菜单
sudo bash pig-nmp.sh status     # 显示系统状态
sudo bash pig-nmp.sh install    # 快速安装 NMP
sudo bash pig-nmp.sh help       # 显示帮助
```

---

### Nginx 管理

#### 安装

选择菜单 `1` → `1`，支持两种安装方式：

**方式一：官方 APT 源安装（推荐）**

- 自动添加 nginx.org 官方 APT 源
- 可选 stable（稳定版）或 mainline（主线版）
- 安装速度快，后续可通过 `apt upgrade` 更新

**方式二：源码编译安装**

- 从 nginx.org 下载源码编译
- 可自定义编译模块（http_image_filter, http_geoip, http_dav, mail 等）
- 默认启用 SSL、HTTP/2、HTTP/3、RealIP、Gzip、Stub Status、Stream 等模块

#### 管理操作

```
Nginx Management
  1) Install Nginx
  2) Uninstall Nginx
  3) Start/Stop/Restart
  4) Reload Configuration
  5) Test Configuration
  6) Status
  0) Back
```

---

### PHP 多版本管理

#### 安装 PHP

选择菜单 `1` → `2`，从 php.net 下载源码编译安装。

**支持的版本：** 8.1 / 8.2 / 8.3 / 8.4

**默认编译的扩展：**
pdo_mysql, mysqli, mbstring, openssl, curl, json, xml, zip, bcmath, opcache, pcntl, posix, tokenizer, ctype, fileinfo, session, filter, hash, gd, intl, soap, sockets, xsl, readline, ftp, bz2, gmp, exif, gettext, sodium, argon2, ldap

> PHP 编译安装通常需要 10-20 分钟，取决于服务器性能。

**多版本共存机制：**

每个 PHP 版本安装到独立目录：

```
/usr/local/php8.1/    # PHP 8.1
/usr/local/php8.2/    # PHP 8.2
/usr/local/php8.3/    # PHP 8.3
/usr/local/php8.4/    # PHP 8.4
```

每个版本运行独立的 php-fpm 进程，监听不同端口或 Unix Socket：

```
PHP 8.1 → /var/run/pig-nmp/php-fpm/php8.1.sock  (端口 9081)
PHP 8.2 → /var/run/pig-nmp/php-fpm/php8.2.sock  (端口 9082)
PHP 8.3 → /var/run/pig-nmp/php-fpm/php8.3.sock  (端口 9083)
PHP 8.4 → /var/run/pig-nmp/php-fpm/php8.4.sock  (端口 9084)
```

#### 设置默认版本

```bash
# 交互式
sudo bash pig-nmp.sh php → 选择 "Set default PHP version"
```

设置后，`php`、`phpize`、`php-config`、`pear`、`pecl` 命令将指向默认版本。

#### php-fpm 调优

可以对每个版本的 php-fpm 进行进程管理调优：

- **pm** = dynamic（推荐）/ static / ondemand
- **pm.max_children** = 最大子进程数
- **pm.start_servers** = 启动时进程数
- **pm.min_spare_servers** = 最小空闲进程
- **pm.max_spare_servers** = 最大空闲进程

#### 为虚拟主机指定 PHP 版本

创建虚拟主机时，会提示选择 PHP 版本。Nginx 配置中的 `fastcgi_pass` 将指向对应版本的 Socket 文件。

---

### MySQL/MariaDB 管理

#### 安装

选择菜单 `1` → `3`，选择 MySQL 或 MariaDB：

**MySQL 版本：** 8.0 / 8.4 / 9.1
**MariaDB 版本：** 10.11 / 11.4 / 11.6

安装过程：
1. 添加官方 APT 源
2. 通过 APT 安装
3. 运行安全初始化向导

#### 安全初始化

安装完成后会自动运行安全配置向导：

- 设置 root 密码（可自动生成）
- 删除匿名用户
- 禁止远程 root 登录
- 删除 test 数据库
- Root 密码保存在 `/etc/pig-nmp/mysql/.root_password`（权限 600）

#### 创建数据库和用户

```
MySQL/MariaDB Management → 4) Create database and user
```

交互式输入：
- 数据库名
- 用户名（默认与数据库名相同）
- 密码（留空自动生成）

---

### Redis 管理

从 redis.io 下载源码编译安装。

**配置项：**
- 监听地址：127.0.0.1:6379
- 持久化：RDB + AOF（默认启用）
- 最大内存：系统内存的 20%
- 淘汰策略：allkeys-lru
- 密码：可选设置

```bash
# 设置 Redis 密码
sudo bash pig-nmp.sh redis → 4) Set password
```

---

### Memcached 管理

从 memcached.org 下载源码编译安装。

**配置项：**
- 监听地址：127.0.0.1:11211
- 最大内存：系统内存的 10%
- 最大连接数：1024

---

### PHP 扩展管理

选择菜单 `4` → `2`（PHP Extension Management）。

**支持的扩展（18+）：**

| 扩展 | 说明 | 系统依赖 |
|------|------|----------|
| imagick | 图像处理（ImageMagick） | libmagickwand-dev, imagemagick |
| redis | Redis 客户端 | - |
| memcached | Memcached 客户端 | libmemcached-dev |
| gd | GD 图像处理 | libgd-dev |
| intl | 国际化 | libicu-dev |
| mongodb | MongoDB 客户端 | libssl-dev |
| swoole | 异步协程框架 | libssl-dev |
| yaml | YAML 解析 | libyaml-dev |
| xdebug | 调试/性能分析 | - |
| grpc | gRPC 框架 | - |
| protobuf | Protocol Buffers | - |
| ssh2 | SSH2 | libssh2-1-dev |
| rdkafka | Kafka 客户端 | librdkafka-dev |
| amqp | AMQP 协议 | librabbitmq-dev |
| pcov | 代码覆盖率 | - |
| excimer | 性能分析 | - |
| mcrypt | 加密（已弃用） | libmcrypt-dev |
| opcache | OPcache（通常已内置） | - |

**安装扩展：**

```bash
# 交互式安装
sudo bash pig-nmp.sh php-ext
# → 选择 PHP 版本 → 输入扩展名
```

**批量安装常用扩展：**

选择 `5) Batch install common extensions`，将自动安装 imagick、redis、memcached、mongodb、swoole、yaml。

---

### ionCube Loader

ionCube 是 PHP 加密代码的运行时加载器，常用于运行加密的商业 PHP 程序。

**安装流程：**

1. 从 ioncube.com 下载 Linux x86_64 Loaders 包
2. 解压到 `/usr/local/ioncube/`
3. 自动匹配已安装的 PHP 版本
4. 将对应版本的 `ioncube_loader_lin_X.Y.so` 复制到 PHP 扩展目录
5. 在 `php.ini` 最前面添加 `zend_extension` 行
6. 重启 php-fpm 并验证

```bash
# 交互式安装
sudo bash pig-nmp.sh ioncube → 1) Install ionCube

# 验证安装成功
/usr/local/php8.3/bin/php -v
# 输出应包含: with the ionCube PHP Loader
```

> **注意：** ionCube 必须作为 `zend_extension` 加载，且必须在所有其他 zend 扩展之前。安装后不能同时使用 SourceGuardian 等其他加密扩展。

---

### phpMyAdmin 管理

#### 安装

前置条件：Nginx + 至少一个 PHP 版本 + MySQL/MariaDB 已安装。

安装流程：
1. 下载 phpMyAdmin 到 `/usr/local/phpmyadmin/`
2. 生成配置文件（含随机 Blowfish Secret）
3. 选择访问方式：
   - **子域名访问**：如 `pma.example.com`（创建独立虚拟主机）
   - **URL路径访问**：如 `example.com/pma`（在现有虚拟主机中添加 location）
4. 安全配置（可选）：
   - IP 白名单
   - HTTP Basic Auth

#### 安全加固

**设置 IP 白名单：**
```
phpMyAdmin Management → 4) Configure security → Set IP whitelist
# 输入允许访问的 IP 或 CIDR（如 192.168.1.0/24）
```

**设置 HTTP Basic Auth：**
```
phpMyAdmin Management → 4) Configure security → Set HTTP Basic Auth
# 输入用户名和密码
```

**更新 phpMyAdmin：**
```
phpMyAdmin Management → 2) Update phpMyAdmin
# 输入新版本号，自动备份配置、更新、恢复配置
```

---

### FTP 服务器管理

#### 安装 vsftpd

支持 APT 安装或源码编译安装。

安装后交互式配置：
- 被动模式端口范围（默认 40000-40100）
- FTP over TLS/SSL（可选）

#### 用户管理

**虚拟用户（推荐）：**

虚拟用户通过 PAM 认证，无需创建系统用户，每个用户可指定独立家目录。

```bash
FTP Server Management → 3) Add FTP user
# 选择 "Virtual user"
# 输入用户名、密码、家目录
```

**系统用户：**

创建 Linux 系统用户，登录 shell 设为 `/usr/sbin/nologin`。

#### 被动模式配置

FTP 被动模式需要开放一段端口范围，并配置服务器公网 IP：

```bash
FTP Server Management → 7) Configure passive mode
# 输入端口范围起止（默认 40000-40100）
# 输入服务器公网 IP
```

> 确保防火墙已开放被动端口范围。

#### SSL/TLS 配置

```bash
FTP Server Management → 8) Configure SSL/TLS
# 自动生成自签名证书
# 或指定已有证书路径
```

---

### 防火墙管理

基于 UFW (Uncomplicated Firewall) 的防火墙管理。

#### 安全预设

| 端口 | 开发环境 | 生产环境 | 严格模式 |
|------|----------|----------|----------|
| 22 (SSH) | 开放 | 开放 | 限制IP |
| 80 (HTTP) | 开放 | 开放 | 开放 |
| 443 (HTTPS) | 开放 | 开放 | 开放 |
| 21 (FTP) | 开放 | 关闭 | 关闭 |
| 3306 (MySQL) | 开放 | 关闭 | 关闭 |
| 6379 (Redis) | 开放 | 关闭 | 关闭 |
| 11211 (Memcached) | 开放 | 关闭 | 关闭 |
| 40000-40100 (FTP被动) | 开放 | 开放 | 关闭 |

```bash
# 应用安全预设
sudo bash pig-nmp.sh firewall → 3) Apply security profile
```

#### 自动配置

```bash
sudo bash pig-nmp.sh firewall → 6) Auto-configure
```

自动检测已安装的服务并配置规则：
- Nginx → 开放 80/443
- FTP → 开放 21 + 被动端口
- MySQL → 阻止 3306（建议通过 SSH 隧道访问）
- Redis → 阻止 6379（仅本地监听）
- Memcached → 阻止 11211（仅本地监听）

---

### 虚拟主机向导

#### 创建虚拟主机

```
Virtual Host Management → 1) Create virtual host
```

向导将依次询问：

1. **域名**：如 `example.com`
2. **文档根目录**：默认 `/home/www/domains/example.com`
3. **PHP 版本**：选择已安装的 PHP 版本（决定 fastcgi_pass 指向）
4. **是否启用 SSL**：是/否
5. **伪静态规则**：可选以下框架的预设规则

**支持的伪静态规则：**

| 框架 | 规则 |
|------|------|
| WordPress | `try_files $uri $uri/ /index.php?$args;` |
| Laravel | `try_files $uri $uri/ /index.php?$query_string;` |
| ThinkPHP | `rewrite ^(.*)$ /index.php?s=$1 last;` |
| Typecho | `rewrite ^(.*)$ /index.php$1 last;` |
| CodeIgniter | `try_files $uri $uri/ /index.php/$uri?$query_string;` |
| Drupal | `try_files $uri /index.php?$query_string;` |

创建完成后，Nginx 配置文件生成在：

```
/etc/pig-nmp/nginx/sites-available/example.com.conf
/etc/pig-nmp/nginx/sites-enabled/example.com.conf  (符号链接)
```

#### 启用/禁用虚拟主机

```
启用：Virtual Host Management → 4) Enable virtual host
禁用：Virtual Host Management → 5) Disable virtual host
```

通过创建/删除 `sites-enabled` 下的符号链接实现，无需修改配置文件。

#### 删除虚拟主机

```
Virtual Host Management → 2) Delete virtual host
```

可选择是否同时删除文档根目录。

---

### SSL 证书向导

#### Let's Encrypt 证书

```
SSL Certificate Management → 1) Issue Let's Encrypt certificate
```

支持三种验证方式：

1. **HTTP (webroot)** — 最常用，自动在网站根目录放置验证文件
2. **DNS (手动)** — 需要手动添加 DNS TXT 记录
3. **DNS (Cloudflare API)** — 自动通过 Cloudflare API 添加 DNS 记录

安装 acme.sh 后自动配置证书续期 cron 任务。

#### 自签名证书

```
SSL Certificate Management → 2) Generate self-signed certificate
```

用于测试环境，浏览器会显示不安全警告。

#### 证书续期

```
SSL Certificate Management → 3) Renew certificate
# 可续期指定域名或全部证书
```

acme.sh 默认会自动续期，此功能用于手动触发续期。

#### 查看证书信息

```
SSL Certificate Management → 6) Show certificate info
# 显示证书的有效期、颁发者等信息
```

---

### 系统管理面板

```
System Manager
  1) System status         — 操作系统、内存、磁盘、负载信息
  2) Services status       — 所有组件运行状态一览
  3) Port status           — 端口占用情况
  4) Quick install NMP     — 一键安装 Nginx + PHP + MySQL
  5) Backup configuration  — 备份所有配置文件
  6) System optimization   — 内核参数、文件描述符优化
```

---

## 配置文件路径

所有配置文件统一存放在 `/etc/pig-nmp/` 下：

| 组件 | 配置文件路径 |
|------|------------|
| Nginx 主配置 | `/etc/pig-nmp/nginx/nginx.conf` |
| 虚拟主机可用 | `/etc/pig-nmp/nginx/sites-available/` |
| 虚拟主机启用 | `/etc/pig-nmp/nginx/sites-enabled/` |
| Nginx 附加配置 | `/etc/pig-nmp/nginx/conf.d/` |
| PHP 配置 | `/etc/pig-nmp/php/{version}/php.ini` |
| php-fpm 配置 | `/etc/pig-nmp/php/{version}/php-fpm.conf` |
| php-fpm Pool | `/etc/pig-nmp/php/{version}/fpm/pool.d/www.conf` |
| MySQL/MariaDB 配置 | `/etc/pig-nmp/mysql/my.cnf` |
| MySQL root 密码 | `/etc/pig-nmp/mysql/.root_password` |
| Redis 配置 | `/etc/pig-nmp/redis/redis.conf` |
| vsftpd 配置 | `/etc/pig-nmp/vsftpd/vsftpd.conf` |
| FTP 虚拟用户 | `/etc/pig-nmp/vsftpd/users/` |
| SSL 证书 | `/etc/pig-nmp/ssl/{domain}/` |

**程序安装路径：**

| 组件 | 安装路径 |
|------|----------|
| Nginx (源码编译) | `/usr/local/nginx/` |
| PHP 各版本 | `/usr/local/php{version}/` |
| Redis | `/usr/local/redis/` |
| Memcached | `/usr/local/memcached/` |
| ionCube Loaders | `/usr/local/ioncube/` |
| phpMyAdmin | `/usr/local/phpmyadmin/` |
| acme.sh | `~/.acme.sh/` |

**日志路径：**

| 日志 | 路径 |
|------|------|
| Nginx 访问日志 | `/var/log/pig-nmp/nginx/access.log` |
| Nginx 错误日志 | `/var/log/pig-nmp/nginx/error.log` |
| 站点访问日志 | `/var/log/pig-nmp/nginx/{domain}.access.log` |
| PHP 错误日志 | `/var/log/pig-nmp/php/php-errors.log` |
| php-fpm 错误日志 | `/var/log/pig-nmp/php-fpm/` |
| MySQL 慢查询日志 | `/var/log/pig-nmp/mysql/slow.log` |
| Redis 日志 | `/var/log/pig-nmp/redis/redis.log` |
| vsftpd 日志 | `/var/log/pig-nmp/vsftpd/vsftpd.log` |
| Pig-NMP 错误日志 | `/var/log/pig-nmp/error.log` |

---

## 端口分配

| 端口 | 服务 | 说明 |
|------|------|------|
| 22 | SSH | 远程管理 |
| 80 | Nginx (HTTP) | 网站访问 |
| 443 | Nginx (HTTPS) | 安全网站访问 |
| 21 | vsftpd (FTP) | 文件传输 |
| 3306 | MySQL/MariaDB | 数据库（建议仅本地） |
| 6379 | Redis | 缓存（建议仅本地） |
| 11211 | Memcached | 缓存（建议仅本地） |
| 9081 | PHP-FPM 8.1 | 备用端口（默认用 Unix Socket） |
| 9082 | PHP-FPM 8.2 | 备用端口 |
| 9083 | PHP-FPM 8.3 | 备用端口 |
| 9084 | PHP-FPM 8.4 | 备用端口 |
| 40000-40100 | FTP 被动模式 | 可自定义范围 |

---

## 镜像加速

如果服务器在中国大陆，可以启用国内镜像加速下载。

编辑 `config.inc.sh`：

```bash
# 将 MIRROR_CN 改为 "true"
MIRROR_CN="true"
```

支持的镜像：
- PHP → sohu 镜像
- Nginx → huawei 镜像
- Redis → huawei 镜像
- phpMyAdmin → huawei 镜像

当镜像下载失败时，会自动回退到官方源。

---

## 常见问题

### Q: PHP 编译失败怎么办？

查看编译日志：

```bash
cat /var/log/pig-nmp/php-{version}-configure.log
cat /var/log/pig-nmp/php-{version}-make.log
```

常见原因：
- 缺少系统依赖 → 运行系统优化或手动安装 `build-essential` 等
- 内存不足 → 添加 swap 分区（脚本会自动为小于 2GB 内存的系统添加 swap）

### Q: 如何在同一服务器运行多个 PHP 版本的网站？

每个虚拟主机的 Nginx 配置中，`fastcgi_pass` 指向不同 PHP 版本的 Socket：

```nginx
# 站点A 使用 PHP 8.2
fastcgi_pass unix:/var/run/pig-nmp/php-fpm/php8.2.sock;

# 站点B 使用 PHP 8.3
fastcgi_pass unix:/var/run/pig-nmp/php-fpm/php8.3.sock;
```

通过虚拟主机向导创建时选择不同 PHP 版本即可自动配置。

### Q: 如何远程连接 MySQL？

**不推荐直接开放 3306 端口。** 建议使用 SSH 隧道：

```bash
ssh -L 3306:127.0.0.1:3306 user@your-server
# 然后在本地连接 127.0.0.1:3306
```

如确需远程连接，在防火墙中开放 3306 并在 MySQL 中授权远程用户。

### Q: ionCube 安装后网站报错？

确保 `php.ini` 中 ionCube 的 `zend_extension` 行在所有其他 zend 扩展之前。检查：

```bash
/usr/local/php8.3/bin/php -v
# 如果报错，检查 php.ini 中 zend_extension 的顺序
```

### Q: Let's Encrypt 证书申请失败？

- 确保域名已正确解析到服务器 IP
- 确保 80 端口可从外网访问
- 检查 Nginx 配置是否正确：`nginx -t`
- 如果使用 DNS 验证，确保 TXT 记录已生效

### Q: FTP 连接超时？

- 检查防火墙是否开放 21 端口和被动端口范围
- 检查被动模式配置中的 `pasv_address` 是否为服务器公网 IP
- 如果使用阿里云/腾讯云，需要在安全组中也开放相应端口

### Q: 如何修改 PHP 配置（upload_max_filesize 等）？

编辑对应版本的 `php.ini`：

```bash
vi /etc/pig-nmp/php/8.3/php.ini
# 修改 upload_max_filesize、memory_limit 等

# 重启 php-fpm
systemctl restart php8.3-fpm
```

---

## 卸载

通过交互式菜单 `8) Uninstall Components` 逐个卸载，或直接删除：

```bash
# 停止所有服务
systemctl stop nginx php*-fpm mysql redis memcached vsftpd 2>/dev/null

# 删除安装文件
rm -rf /usr/local/nginx /usr/local/php* /usr/local/redis /usr/local/memcached
rm -rf /usr/local/phpmyadmin /usr/local/ioncube

# 删除配置文件
rm -rf /etc/pig-nmp

# 删除日志
rm -rf /var/log/pig-nmp

# 删除数据（谨慎！）
rm -rf /var/lib/pig-nmp

# 删除 systemd 服务
rm -f /etc/systemd/system/nginx.service
rm -f /etc/systemd/system/php*-fpm.service
rm -f /etc/systemd/system/redis.service
rm -f /etc/systemd/system/memcached.service
rm -f /etc/systemd/system/vsftpd.service
systemctl daemon-reload

# 如果通过 APT 安装了 Nginx/MySQL
apt remove --purge nginx mysql-server mariadb-server vsftpd ufw -y
```

---

## License / 许可证

[Apache-2.0 license](https://github.com/laingyulee/pig-nmp#Apache-2.0-1-ov-file)
