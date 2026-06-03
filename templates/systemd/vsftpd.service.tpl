[Unit]
Description=vsftpd FTP server
After=network.target

[Service]
Type=simple
ExecStart={{VSFTPD_BIN}} {{VSFTPD_CONF}}
Restart=on-failure
RestartSec=5s
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
