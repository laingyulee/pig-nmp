[PHP]
engine = On
short_open_tag = Off
precision = 14
output_buffering = 4096
zlib.output_compression = Off
implicit_flush = Off
serialize_precision = -1

disable_functions = pcntl_alarm,pcntl_fork,pcntl_waitpid,pcntl_wait,pcntl_wifexited,pcntl_wifsignaled,pcntl_wifstopped,pcntl_wexitstatus,pcntl_wtermsig,pcntl_wstopsig,pcntl_signal,pcntl_signal_get_handler,pcntl_signal_dispatch,pcntl_sigprocmask,pcntl_sigwaitinfo,pcntl_sigtimedwait,pcntl_exec,pcntl_getpriority,pcntl_setpriority,pcntl_async_signals

expose_php = Off

max_execution_time = {{MAX_EXECUTION_TIME}}
max_input_time = 300
memory_limit = {{MEMORY_LIMIT}}
error_reporting = E_ALL & ~E_DEPRECATED & ~E_STRICT
display_errors = Off
display_startup_errors = Off
log_errors = On
log_errors_max_len = 1024
ignore_repeated_errors = On
ignore_repeated_source = On
report_memleaks = On
error_log = {{LOG_DIR}}/php-fpm/php-errors.log

variables_order = "GPCS"
request_order = "GP"
register_argc_argv = Off
auto_globals_jit = On

post_max_size = {{UPLOAD_MAX_SIZE}}
auto_prepend_file =
auto_append_file =
default_mimetype = "text/html; charset=UTF-8"

file_uploads = On
upload_max_filesize = {{UPLOAD_MAX_SIZE}}
max_file_uploads = 20

allow_url_fopen = On
allow_url_include = Off

[Date]
date.timezone = {{TIMEZONE}}

[Session]
session.save_handler = files
session.save_path = "/tmp"
session.use_strict_mode = 1
session.use_cookies = 1
session.use_only_cookies = 1
session.name = PHPSESSID
session.auto_start = 0
session.cookie_lifetime = 0
session.cookie_path = /
session.cookie_domain =
session.cookie_httponly = 1
session.cookie_samesite = Strict
session.serialize_handler = php
session.gc_probability = 1
session.gc_divisor = 1000
session.gc_maxlifetime = 1440

[opcache]
opcache.enable=1
opcache.enable_cli=0
opcache.memory_consumption=128
opcache.interned_strings_buffer=8
opcache.max_accelerated_files=10000
opcache.revalidate_freq=60
opcache.fast_shutdown=1
opcache.save_comments=1

[mysqlnd]
mysqlnd.collect_memory_statistics = Off
mysqlnd.collect_statistics = Off

[mbstring]
mbstring.language = UTF-8
mbstring.internal_encoding = UTF-8

[curl]
curl.cainfo = /etc/ssl/certs/ca-certificates.crt

[openssl]
openssl.cafile = /etc/ssl/certs/ca-certificates.crt
openssl.capath = /etc/ssl/certs
