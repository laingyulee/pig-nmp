[Unit]
Description=The nginx HTTP and reverse proxy server
After=network.target remote-fs.target nss-lookup.target

[Service]
Type=forking
PIDFile={{NGINX_PID}}
ExecStartPre={{NGINX_BIN}} -t -c {{NGINX_ETC_DIR}}/nginx.conf
ExecStart={{NGINX_BIN}} -c {{NGINX_ETC_DIR}}/nginx.conf
ExecReload=/bin/kill -s HUP $MAINPID
ExecStop=/bin/kill -s QUIT $MAINPID
PrivateTmp=true
Restart=on-failure
RestartSec=5s
LimitNOFILE=1048576

[Install]
WantedBy=multi-user.target
