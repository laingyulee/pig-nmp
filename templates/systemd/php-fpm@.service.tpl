[Unit]
Description=The PHP {{PHP_VER}} FastCGI Process Manager
After=network.target

[Service]
Type=notify
PIDFile={{PHP_FPM_PID}}
ExecStart={{PHP_PREFIX}}/sbin/php-fpm --nodaemonize --fpm-config {{PHP_ETC_DIR}}/php-fpm.conf
ExecReload=/bin/kill -USR2 $MAINPID
PrivateTmp=true
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
