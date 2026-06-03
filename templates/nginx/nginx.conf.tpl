user {{NGINX_USER}};
worker_processes {{NGINX_WORKER_PROCESSES}};
error_log {{LOG_DIR}}/nginx/error.log warn;
pid {{RUN_DIR}}/nginx.pid;

worker_rlimit_nofile 1048576;

events {
    worker_connections 65535;
    use epoll;
    multi_accept on;
}

http {
    include {{NGINX_ETC_DIR}}/mime.types;
    default_type application/octet-stream;

    server_names_hash_bucket_size 128;
    client_header_buffer_size 32k;
    large_client_header_buffers 4 32k;
    client_max_body_size 64m;

    sendfile on;
    tcp_nopush on;
    tcp_nodelay on;
    keepalive_timeout 60;
    server_tokens off;

    gzip on;
    gzip_min_length 1k;
    gzip_buffers 4 16k;
    gzip_http_version 1.1;
    gzip_comp_level 4;
    gzip_types text/plain text/css application/json application/javascript text/xml application/xml application/xml+rss text/javascript image/svg+xml;
    gzip_vary on;
    gzip_proxied any;

    open_file_cache max=65535 inactive=60s;
    open_file_cache_valid 90s;
    open_file_cache_min_uses 1;
    open_file_cache_errors on;

    fastcgi_connect_timeout 300;
    fastcgi_send_timeout 300;
    fastcgi_read_timeout 300;
    fastcgi_buffer_size 64k;
    fastcgi_buffers 4 64k;
    fastcgi_busy_buffers_size 128k;
    fastcgi_temp_file_write_size 256k;

    proxy_connect_timeout 300;
    proxy_read_timeout 300;
    proxy_send_timeout 300;
    proxy_buffer_size 64k;
    proxy_buffers 4 64k;
    proxy_busy_buffers_size 128k;

    log_format main '$remote_addr - $remote_user [$time_local] "$request" '
                    '$status $body_bytes_sent "$http_referer" '
                    '"$http_user_agent" "$http_x_forwarded_for"';

    access_log {{LOG_DIR}}/nginx/access.log main;

    include {{NGINX_ETC_DIR}}/conf.d/*.conf;
    include {{NGINX_SITES_ENABLED}}/*.conf;
}
