[Unit]
Description=Memcached Daemon
After=network.target

[Service]
Type=simple
User=memcached
Group=memcached
ExecStart={{MEMCACHED_BIN}} -p 11211 -u memcached -m 64 -c 1024 -P {{MEMCACHED_PID}}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
