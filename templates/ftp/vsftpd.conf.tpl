# Pig-NMP vsftpd Configuration

listen=YES
listen_ipv6=NO

anonymous_enable=NO
local_enable=YES
write_enable=YES
local_umask=022
dirmessage_enable=YES
use_localtime=YES
xferlog_enable=YES
connect_from_port_20=YES
xferlog_std_format=YES

chroot_local_user=YES
allow_writeable_chroot=YES

guest_enable=YES
guest_username=www-data
virtual_use_local_privs=YES
user_config_dir={{FTP_USER_DIR}}

pasv_enable=YES
pasv_min_port={{FTP_PASV_MIN_PORT}}
pasv_max_port={{FTP_PASV_MAX_PORT}}
pasv_address={{FTP_PASV_ADDRESS}}

secure_chroot_dir=/var/run/vsftpd/empty
pam_service_name=vsftpd.virtual

dual_log_enable=YES
vsftpd_log_file={{LOG_DIR}}/vsftpd/vsftpd.log
xferlog_file={{LOG_DIR}}/vsftpd/xferlog.log

ssl_enable=NO
#rsa_cert_file={{FTP_ETC_DIR}}/ssl/vsftpd.crt
#rsa_private_key_file={{FTP_ETC_DIR}}/ssl/vsftpd.key

seccomp_sandbox=NO
utf8_filesystem=YES
