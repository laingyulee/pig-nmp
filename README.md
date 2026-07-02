<p align="center">
  <img src="https://img.shields.io/badge/version-1.1.0-blue" alt="version">
  <img src="https://img.shields.io/badge/platform-Debian%2FUbuntu-brightgreen" alt="platform">
  <img src="https://img.shields.io/badge/license-Apache%202.0-orange" alt="license">
  <img src="https://img.shields.io/badge/arch-x86__64-red" alt="arch">
</p>

<h1 align="center">Pig-NMP</h1>

<p align="center">
  <strong>Nginx + MySQL/MariaDB + PHP Installer Script</strong><br>
  <sub>Debian/Ubuntu LNMP Management Tool</sub>
</p>

---

## Features

- **Nginx** — APT / Source install
- **PHP** — APT (SURY) / Source, multi-version 8.1–8.5, Composer included
- **MySQL / MariaDB** — APT install
- **Redis** — APT / Source install
- **Virtual Host Wizard** — One-command vhost setup
- **SSL Wizard** — acme.sh / Let's Encrypt
- **System Manager** — Service control & status panel
- **PHP Extensions** — One-click install + FPM diagnostics

## Table of Contents

- [Quick Start](#quick-start)
- [Directory Structure](#directory-structure)
- [CLI Usage](#cli-usage)
- [Virtual Host Management](#virtual-host-management)
- [SSL Certificate](#ssl-certificate)
- [PHP Management](#php-management)
- [Redis](#redis)
- [System Manager](#system-manager)
- [Config Paths](#config-paths)
- [FAQ](#faq)
- [Uninstall](#uninstall)
- [License](#license)
- [中文说明](#中文说明)

---

## Quick Start

```bash
# Download
wget https://github.com/laingyulee/pig-nmp/archive/refs/heads/main.zip
unzip main.zip && cd pig-nmp-main

# Run installer
chmod +x pig-nmp.sh
./pig-nmp.sh
```

Main menu:

```
1) Install/Update Components
2) Manage Virtual Hosts
3) Configure SSL Certificates
4) PHP Version & Extension Management
5) System Status & Manager
6) Uninstall Components
```

## Directory Structure

```
pig-nmp/
├── pig-nmp.sh          # Entry point
├── config.inc.sh       # Global config
├── lib/
│   ├── common.sh       # Utility functions
│   ├── color.sh        # Terminal colors
│   ├── download.sh     # Download helpers
│   └── os.sh           # OS detection
├── modules/
│   ├── nginx.sh        # Nginx installer
│   ├── php.sh          # PHP installer
│   ├── php-ext.sh      # PHP extensions
│   ├── mysql.sh        # MySQL/MariaDB
│   └── redis.sh        # Redis installer
├── wizard/
│   ├── vhost.sh        # Virtual host wizard
│   ├── ssl.sh          # SSL wizard
│   └── manager.sh      # System manager
├── templates/
│   ├── nginx/          # Nginx templates
│   ├── php/            # PHP-FPM templates
│   ├── mysql/          # MySQL templates
│   └── systemd/        # Systemd unit files
└── conf/
    ├── versions.conf   # Version pinning
    └── mirrors.conf    # Mirror sources
```

## CLI Usage

```bash
./pig-nmp.sh <command> [options]
```

| Command | Description |
|---------|-------------|
| `nginx` | Install / manage Nginx |
| `php` | Install / manage PHP |
| `mysql` | Install / manage MySQL / MariaDB |
| `redis` | Install / manage Redis |
| `vhost` | Create / manage virtual hosts |
| `ssl` | Issue / manage SSL certificates |
| `status` | Show system status panel |
| `install` | Run interactive installer |
| `help` | Show help |

## Virtual Host Management

```bash
./pig-nmp.sh vhost add       # Add virtual host
./pig-nmp.sh vhost del       # Remove virtual host
./pig-nmp.sh vhost list      # List all vhosts
```

## SSL Certificate

```bash
./pig-nmp.sh ssl issue example.com    # Issue certificate
./pig-nmp.sh ssl renew example.com    # Renew certificate
./pig-nmp.sh ssl list                 # List certificates
```

## PHP Management

```bash
./pig-nmp.sh php install 8.3          # Install PHP 8.3
./pig-nmp.sh php list                 # List installed versions
./pig-nmp.sh php ext install redis    # Install extension
./pig-nmp.sh php ext list             # List available extensions
```

**Supported extensions:**

| Category | Extensions |
|----------|-----------|
| Database | `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `mysqli` |
| Common | `mbstring`, `curl`, `fileinfo`, `xml`, `xmlwriter`, `xmlreader` |
| Math/Zip | `bcmath`, `zip` |
| Graphics | `gd`, `imagick` |
| Network | `soap` |
| Optimization | `opcache` |
| Debug | `xdebug` |
| Cache | `redis` |

## Redis

```bash
./pig-nmp.sh redis install    # Install Redis
./pig-nmp.sh redis start      # Start Redis
./pig-nmp.sh redis stop       # Stop Redis
./pig-nmp.sh redis status     # Check status
```

## System Manager

```bash
./pig-nmp.sh status           # Interactive manager panel
```

## Config Paths

| Component | Path |
|-----------|------|
| Config | `/etc/pig-nmp/{nginx,php,mysql,redis,ssl}/` |
| Nginx | `/usr/local/nginx/` |
| PHP | `/usr/local/php*/` |
| Redis | `/usr/local/redis/` |
| acme.sh | `/usr/local/acme.sh/` |
| PHP-FPM | Port `9081`–`9084` |

**Default ports:** 80 (HTTP), 443 (HTTPS), 3306 (MySQL), 6379 (Redis)

## FAQ

**Q: Can I install multiple PHP versions?**
A: Yes. Install PHP 8.1 through 8.5 side-by-side, each with its own FPM pool on ports 9081–9084.

**Q: Which MySQL versions are supported?**
A: MySQL 5.7/8.0/8.1 and MariaDB 10.x/11.x via APT.

**Q: How do I switch Nginx between APT and source?**
A: Use the installer menu. Source install places Nginx in `/usr/local/nginx/`; APT install uses system paths.

**Q: Does it support ARM/aarch64?**
A: Currently only x86_64 is supported.

## Uninstall

```bash
./pig-nmp.sh uninstall
```

Or remove manually:

```bash
# Stop services
systemctl stop nginx php-fpm mysql redis

# Remove binaries
rm -rf /usr/local/nginx /usr/local/php* /usr/local/redis /usr/local/acme.sh

# Remove config
rm -rf /etc/pig-nmp

# Remove Nginx source install (if applicable)
rm -rf /etc/nginx
```

## License

[Apache License 2.0](LICENSE)

---

# 中文说明

## 快速开始

```bash
# 下载
wget https://github.com/laingyulee/pig-nmp/archive/refs/heads/main.zip
unzip main.zip && cd pig-nmp-main

# 运行安装
chmod +x pig-nmp.sh
./pig-nmp.sh
```

主菜单：

```
1) 安装/更新组件
2) 管理虚拟主机
3) 配置 SSL 证书
4) PHP 版本与扩展管理
5) 系统状态与管理
6) 卸载组件
```

## 目录结构

```
pig-nmp/
├── pig-nmp.sh          # 入口脚本
├── config.inc.sh       # 全局配置
├── lib/                # 基础库
├── modules/            # 组件安装模块
├── wizard/             # 交互向导
├── templates/          # 配置模板
└── conf/               # 版本与镜像配置
```

## 命令行用法

```bash
./pig-nmp.sh <命令> [选项]
```

| 命令 | 说明 |
|------|------|
| `nginx` | 安装/管理 Nginx |
| `php` | 安装/管理 PHP |
| `mysql` | 安装/管理 MySQL/MariaDB |
| `redis` | 安装/管理 Redis |
| `vhost` | 创建/管理虚拟主机 |
| `ssl` | 签发/管理 SSL 证书 |
| `status` | 显示系统状态面板 |
| `install` | 运行交互安装 |
| `help` | 显示帮助 |

## 虚拟主机管理

```bash
./pig-nmp.sh vhost add       # 添加虚拟主机
./pig-nmp.sh vhost del       # 删除虚拟主机
./pig-nmp.sh vhost list      # 列出所有虚拟主机
```

## SSL 证书

```bash
./pig-nmp.sh ssl issue example.com    # 签发证书
./pig-nmp.sh ssl renew example.com    # 续期证书
./pig-nmp.sh ssl list                 # 列出证书
```

## PHP 管理

```bash
./pig-nmp.sh php install 8.3          # 安装 PHP 8.3
./pig-nmp.sh php list                 # 列出已安装版本
./pig-nmp.sh php ext install redis    # 安装扩展
./pig-nmp.sh php ext list             # 列出可用扩展
```

**支持的 PHP 扩展：** `pdo_mysql`, `pdo_pgsql`, `pdo_sqlite`, `mysqli`, `mbstring`, `curl`, `fileinfo`, `xml`, `xmlwriter`, `xmlreader`, `bcmath`, `zip`, `gd`, `imagick`, `soap`, `opcache`, `xdebug`, `redis`

## Redis

```bash
./pig-nmp.sh redis install    # 安装 Redis
./pig-nmp.sh redis start      # 启动 Redis
./pig-nmp.sh redis stop       # 停止 Redis
./pig-nmp.sh redis status     # 查看状态
```

## 配置路径

| 组件 | 路径 |
|------|------|
| 配置文件 | `/etc/pig-nmp/{nginx,php,mysql,redis,ssl}/` |
| Nginx | `/usr/local/nginx/` |
| PHP | `/usr/local/php*/` |
| Redis | `/usr/local/redis/` |
| acme.sh | `/usr/local/acme.sh/` |
| PHP-FPM | 端口 `9081`–`9084` |

**默认端口：** 80 (HTTP), 443 (HTTPS), 3306 (MySQL), 6379 (Redis)

## 卸载

```bash
./pig-nmp.sh uninstall
```

或手动卸载：

```bash
systemctl stop nginx php-fpm mysql redis
rm -rf /usr/local/nginx /usr/local/php* /usr/local/redis /usr/local/acme.sh
rm -rf /etc/pig-nmp
rm -rf /etc/nginx
```

## 许可证

[Apache License 2.0](LICENSE)
