server {
    listen 80;
    server_name {{DOMAIN}};

    root {{DOCUMENT_ROOT}};
    index index.php index.html index.htm;

    access_log {{LOG_DIR}}/nginx/{{DOMAIN}}.access.log;
    error_log {{LOG_DIR}}/nginx/{{DOMAIN}}.error.log;

    # REWRITE_RULES_MARKER

    location / {
        try_files $uri $uri/ =404;
    }
PHP_LOCATION_BLOCK
    location ~* \.(js|css|png|jpg|jpeg|gif|ico|svg|woff|woff2|ttf|eot)$ {
        expires 30d;
        add_header Cache-Control "public, immutable";
        access_log off;
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

    include /etc/pig-nmp/nginx/conf.d/phpmyadmin.conf;
}
