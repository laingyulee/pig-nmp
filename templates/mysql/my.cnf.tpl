# Pig-NMP MySQL/MariaDB Configuration
# Type: {{DB_TYPE}}

[client]
port = 3306
socket = /var/run/mysqld/mysqld.sock
default-character-set = utf8mb4

[mysql]
default-character-set = utf8mb4

[mysqld]
user = mysql
pid-file = /var/run/mysqld/mysqld.pid
socket = /var/run/mysqld/mysqld.sock
port = 3306
basedir = /usr
datadir = {{MYSQL_DATA_DIR}}
tmpdir = /tmp

character-set-server = utf8mb4
collation-server = utf8mb4_unicode_ci
init_connect = 'SET NAMES utf8mb4'

skip-external-locking
skip-name-resolve

bind-address = 127.0.0.1

max_connections = {{MAX_CONNECTIONS}}
max_connect_errors = 100
connect_timeout = 10
wait_timeout = 600
interactive_timeout = 600

back_log = 512
thread_cache_size = 64
table_open_cache = 4096
table_definition_cache = 2048
open_files_limit = 65535

sort_buffer_size = 2M
join_buffer_size = 2M
read_buffer_size = 2M
read_rnd_buffer_size = 4M
bulk_insert_buffer_size = 32M

tmp_table_size = 64M
max_heap_table_size = 64M

query_cache_type = 0
query_cache_size = 0

slow_query_log = 1
slow_query_log_file = {{LOG_DIR}}/mysql/slow.log
long_query_time = 2

log_error = {{LOG_DIR}}/mysql/error.log

server-id = {{SERVER_ID}}
log_bin = mysql-bin
binlog_format = ROW
binlog_cache_size = 4M
max_binlog_size = 100M
binlog_expire_logs_seconds = 604800

sync_binlog = 1
innodb_flush_log_at_trx_commit = 2

innodb_buffer_pool_size = {{INNODB_BUFFER_POOL}}
innodb_buffer_pool_instances = 4
innodb_log_file_size = 256M
innodb_log_buffer_size = 16M
innodb_flush_method = O_DIRECT
innodb_file_per_table = 1
innodb_read_io_threads = 8
innodb_write_io_threads = 8
innodb_io_capacity = 400
innodb_io_capacity_max = 800
innodb_lock_wait_timeout = 30

[mysqldump]
quick
max_allowed_packet = 64M

[myisamchk]
key_buffer_size = 64M
sort_buffer_size = 64M
read_buffer = 16M
write_buffer = 16M
