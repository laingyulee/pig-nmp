server {
    listen 80 default_server;
    server_name _;

    root /home/www/default;
    index index.html index.htm;

    access_log {{LOG_DIR}}/nginx/default.access.log;
    error_log {{LOG_DIR}}/nginx/default.error.log;

    location / {
        try_files $uri $uri/ =404;
    }

    location ~ /\. {
        deny all;
        access_log off;
        log_not_found off;
    }

    location = /favicon.ico {
        access_log off;
        log_not_found off;
    }

    location = /robots.txt {
        access_log off;
        log_not_found off;
    }
}
