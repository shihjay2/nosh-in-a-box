#!/bin/sh
# ssl installation script for nosh-in-a-box

set -e

WEB_CONF=/etc/apache2/sites-enabled
UBUNTU_VER=$(lsb_release -rs)

# Check if running as root user
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root.  Aborting." 1>&2
	exit 1
fi

read -e -p "Enter your domain name (example.com): " -i "" DOMAIN

if [[ ! -z $DOMAIN ]]; then
	git clone https://github.com/letsencrypt/letsencrypt /opt/letsencrypt
	cd /opt/letsencrypt
	./letsencrypt-auto --apache -d $DOMAIN

	if [ -e "$WEB_CONF"/nosh.conf ]; then
		rm "$WEB_CONF"/nosh.conf
	fi
	touch "$WEB_CONF"/nosh.conf
	APACHE_CONF="<VirtualHost _default_:80>
		ServerName $DOMAIN
		DocumentRoot /var/www/html
		ErrorLog ${APACHE_LOG_DIR}/error.log
		CustomLog ${APACHE_LOG_DIR}/access.log combined
	</VirtualHost>
	<IfModule mod_ssl.c>
		<VirtualHost _default_:443>
			ServerName $DOMAIN
			DocumentRoot /var/www/html
			ErrorLog ${APACHE_LOG_DIR}/error.log
			CustomLog ${APACHE_LOG_DIR}/access.log combined
			SSLEngine on
			SSLProtocol all -SSLv2 -SSLv3
			SSLCertificateFile /etc/ssl/certs/ssl-cert-snakeoil.pem
	        SSLCertificateKeyFile /etc/ssl/private/ssl-cert-snakeoil.key
			<FilesMatch \"\.(cgi|shtml|phtml|php)$\">
				SSLOptions +StdEnvVars
			</FilesMatch>
			<Directory /usr/lib/cgi-bin>
				SSLOptions +StdEnvVars
	        </Directory>
			BrowserMatch \"MSIE [2-6]\" \
			nokeepalive ssl-unclean-shutdown \
			downgrade-1.0 force-response-1.0
			BrowserMatch \"MSIE [17-9]\" ssl-unclean-shutdown
		</VirtualHost>
	</IfModule>
	Alias /nosh $NEWNOSH/public
	<Directory $NEWNOSH/public>
		Options Indexes FollowSymLinks MultiViews
		AllowOverride All"
	if [ "$APACHE_VER" = "4" ]; then
		APACHE_CONF="$APACHE_CONF
		Require all granted"
	else
		APACHE_CONF="$APACHE_CONF
		Order allow,deny
		allow from all"
	fi
	APACHE_CONF="$APACHE_CONF
		RewriteEngine On
		RewriteBase /nosh/
		# Redirect Trailing Slashes...
		RewriteRule ^(.*)/$ /\$1 [L,R=301]
		RewriteRule ^ - [E=HTTP_AUTHORIZATION:%{HTTP:Authorization}]
		# Handle Front Controller...
		RewriteCond %{REQUEST_FILENAME} !-d
		RewriteCond %{REQUEST_FILENAME} !-f
		RewriteRule ^ index.php [L]"
	if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
		APACHE_CONF="$APACHE_CONF
		<IfModule mod_php7.c>"
	else
		APACHE_CONF="$APACHE_CONF
		<IfModule mod_php5.c>"
	fi
	APACHE_CONF="$APACHE_CONF
			php_value upload_max_filesize 512M
			php_value post_max_size 512M
			php_flag magic_quotes_gpc off
			php_flag register_long_arrays off
		</IfModule>
	</Directory>"
	echo "$APACHE_CONF" >> "$WEB_CONF"/nosh.conf
	echo "NOSH ChartingSystem Apache configuration file set."
	$APACHE >> $LOG 2>&1
	echo "Restarting Apache service."
fi
