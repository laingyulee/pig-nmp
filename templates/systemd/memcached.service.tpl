[Unit]
Description=Memcached Daemon
After=network.target

[Service]
Type=simple
User=memcached
Group=memcached
ExecStart={{MEMCACHED_BIN}} {{MEMCACHED_CONF}}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
