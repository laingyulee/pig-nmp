[Unit]
Description=Redis In-Memory Data Store
After=network.target

[Service]
Type=simple
PIDFile={{REDIS_PID}}
User=redis
Group=redis
ExecStart={{REDIS_BIN}} {{REDIS_CONF}} --daemonize no
ExecStop={{REDIS_CLI}} shutdown
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
