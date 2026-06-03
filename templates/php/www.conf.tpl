[{{POOL_NAME}}]
user = {{PHP_FPM_USER}}
group = {{PHP_FPM_GROUP}}

listen = {{PHP_FPM_LISTEN}}
listen.owner = {{PHP_FPM_USER}}
listen.group = {{PHP_FPM_GROUP}}
listen.mode = 0660

pm = {{PHP_FPM_PM}}
pm.max_children = {{PHP_FPM_PM_MAX_CHILDREN}}
pm.start_servers = {{PHP_FPM_PM_START_SERVERS}}
pm.min_spare_servers = {{PHP_FPM_PM_MIN_SPARE}}
pm.max_spare_servers = {{PHP_FPM_PM_MAX_SPARE}}
pm.max_requests = {{PHP_FPM_PM_MAX_REQUESTS}}
pm.process_idle_timeout = 10s

request_terminate_timeout = 300
request_slowlog_timeout = 5s
slowlog = {{LOG_DIR}}/php-fpm/slow-{{POOL_NAME}}.log

php_admin_value[error_log] = {{LOG_DIR}}/php-fpm/{{POOL_NAME}}-error.log
php_admin_flag[log_errors] = on

php_value[session.save_handler] = files
php_value[session.save_path] = /tmp
php_value[soap.wsdl_cache_dir] = /tmp
php_value[opcache.file_cache] = /tmp

env[HOSTNAME] = $HOSTNAME
env[PATH] = /usr/local/bin:/usr/bin:/bin
env[TMP] = /tmp
env[TMPDIR] = /tmp
env[TEMP] = /tmp
