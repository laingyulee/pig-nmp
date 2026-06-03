;;;;;;;;;;;;;;;;;;;;;
; FPM Configuration ;
;;;;;;;;;;;;;;;;;;;;;

[global]
pid = {{PHP_FPM_PID}}
error_log = {{PHP_FPM_ERROR_LOG}}
log_level = warning

emergency_restart_threshold = 10
emergency_restart_interval = 1m
process_control_timeout = 10s
daemonize = yes

include={{PHP_ETC_DIR}}/fpm/pool.d/*.conf
