#!/bin/sh
# install script for nosh-in-a-box

set -e

# Constants and paths
LOGDIR=/var/log/nosh2
LOG=$LOGDIR/nosh2_installation_log
LELOG=$LOGDIR/le-renew.log
NOSHCRON=/etc/cron.d/nosh-cs
WEB=/var/www
MYSQL_DATABASE=nosh
NOSH_DIR=/noshdocuments
NEWNOSH=$NOSH_DIR/nosh2
NEWNOSHTEST=$NEWNOSH/artisan
NEWCONFIGDATABASE=$NEWNOSH/.env
NOSHDIRFILE=$NEWNOSH/.noshdir
WEB_GROUP=www-data
WEB_USER=www-data
WEB_CONF=/etc/apache2/conf-enabled
FTPIMPORT=/srv/ftp/shared/import
FTPEXPORT=/srv/ftp/shared/export
UBUNTU_VER=$(lsb_release -rs)

log_only () {
	echo "$1"
	echo "`date`: $1" >> $LOG
}

unable_exit () {
	echo "$1"
	echo "`date`: $1" >> $LOG
	echo "EXITING.........."
	echo "`date`: EXITING.........." >> $LOG
	exit 1
}

get_settings () {
	echo `grep -i "^[[:space:]]*$1[[:space:]=]" $2 | cut -d \= -f 2 | cut -d \; -f 1 | sed "s/[ 	'\"]//gi"`
}

insert_settings () {
	sed -i 's%^[ 	]*'"$1"'[ 	=].*$%'"$1"' = '"$2"'%' "$3"
}

# Check if running as root user
if [[ $EUID -ne 0 ]]; then
	echo "This script must be run as root.  Aborting." 1>&2
	exit 1
fi

# Create log files if it doesn't exist
if [ ! -d $LOGDIR ]; then
	mkdir -p $LOGDIR
	touch $LOG
	touch $LELOG
fi

# If NOSH directory exists, exit
if [ -d $NOSH_DIR ]; then
	exit 0
fi

# Ask questions.

echo "Welcome to NOSH in a Box!"
echo "You're seeing this because this is the first time the system has booted."
echo "Let's get started..."
if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
	read -e -p "Enter your username (for SSH, MySQL, and phpMyAdmin): " -i "" USERNAME
else
	echo "'root' is the username to access MySQL and phpMyAdmin"
	read -e -p "Enter your username (for SSH): " -i "" USERNAME
fi
read -e -p "Enter your MySQL password (please remember this!): " -i "" MYSQL_PASSWORD
read -e -p "Enter your domain name (example.com): " -i "" DOMAIN

# Add username
adduser $USERNAME
adduser $USERNAME sudo

# Check Ubuntu version

if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
	APACHE="systemctl restart apache2"
	SSH="systemctl restart sshd.service"
	MCRYPT="phpenmod mcrypt"
	IMAP="phpenmod imap"
else
	APACHE="service apache2 restart"
	SSH="service ssh restart"
	MCRYPT="php5enmod mcrypt"
	IMAP="php5enmod imap"
fi

# Check apache version
APACHE_VER=$(apache2 -v | awk -F"[..]" 'NR<2{print $2}')

# Create cron scripts
if [ -f $NOSHCRON ]; then
	rm -rf $NOSHCRON
fi
touch $NOSHCRON
echo "*/10 *  * * *   root    $NEWNOSH/noshfax" >> $NOSHCRON
echo "*/1 *   * * *   root    $NEWNOSH/noshreminder" >> $NOSHCRON
echo "0 0     * * *   root    $NEWNOSH/noshbackup" >> $NOSHCRON
if [[ ! -z $DOMAIN ]]; then
	echo "30 0    * * 1   root    /usr/local/bin/certbot-auto renew >>  /var/log/le-renew.log" >> $NOSHCRON
fi
chown root.root $NOSHCRON
chmod 644 $NOSHCRON
log_only "Created NOSH ChartingSystem cron scripts."

# Set up SFTP
groupadd ftpshared
log_only "Group ftpshared does not exist.  Making group."
mkdir -p $FTPIMPORT
mkdir -p $FTPEXPORT
chown -R root:ftpshared /srv/ftp/shared
chmod 755 /srv/ftp/shared
chmod -R 775 $FTPIMPORT
chmod -R 775 $FTPEXPORT
chmod g+s $FTPIMPORT
chmod g+s $FTPEXPORT
log_only "The NOSH ChartingSystem SFTP directories have been created."
/usr/bin/gpasswd -a www-data ftpshared
cp /etc/ssh/sshd_config /etc/ssh/sshd_config.bak
log_only "Backup of SSH config file created."
sed -i '/Subsystem/s/^/#/' /etc/ssh/sshd_config
echo '
Subsystem sftp internal-sftp' >> /etc/ssh/sshd_config
echo 'Match Group ftpshared' >> /etc/ssh/sshd_config
echo 'ChrootDirectory /srv/ftp/shared' >> /etc/ssh/sshd_config
echo 'X11Forwarding no' >> /etc/ssh/sshd_config
echo 'AllowTCPForwarding no' >> /etc/ssh/sshd_config
echo 'ForceCommand internal-sftp' >> /etc/ssh/sshd_config
log_only "SSH config file updated."
log_only "Restarting SSH server service"
$SSH >> $LOG 2>&1

# Install MySQL and phpMyAdmin
if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
	log_only "Installing MariaDB and phpMyAdmin..."
	# Add Maria PPA
	apt-key adv --recv-keys --keyserver hkp://keyserver.ubuntu.com:80 0xF1656F24C74CD1D8
	add-apt-repository 'deb [arch=amd64,i386,ppc64el] http://ftp.osuosl.org/pub/mariadb/repo/10.1/ubuntu xenial main'
	apt-get update
	# Set The Automated Root Password
	export DEBIAN_FRONTEND=noninteractive
	debconf-set-selections <<< "mariadb-server-10.1 mysql-server/data-dir select ''"
	debconf-set-selections <<< "mariadb-server-10.1 mysql-server/root_password password $MYSQL_PASSWORD"
	debconf-set-selections <<< "mariadb-server-10.1 mysql-server/root_password_again password $MYSQL_PASSWORD"
	apt-get install -y mariadb-server mariadb-client
	# Set default collation and character set
	echo "[mysqld]
character_set_server = 'utf8'
collation_server = 'utf8_general_ci'" >> /etc/mysql/my.cnf
	# Configure Maria Remote Access
	sed -i '/^bind-address/s/bind-address.*=.*/bind-address = 0.0.0.0/' /etc/mysql/my.cnf
	mysql --user="root" --password="$MYSQL_PASSWORD" -e "GRANT ALL ON *.* TO root@'0.0.0.0' IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION;"
	systemctl restart mysql
	mysql --user="root" --password="$MYSQL_PASSWORD" -e "CREATE USER '$USERNAME'@'0.0.0.0' IDENTIFIED BY '$MYSQL_PASSWORD';"
	mysql --user="root" --password="$MYSQL_PASSWORD" -e "GRANT ALL ON *.* TO '$USERNAME'@'0.0.0.0' IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION;"
	mysql --user="root" --password="$MYSQL_PASSWORD" -e "GRANT ALL ON *.* TO '$USERNAME'@'%' IDENTIFIED BY '$MYSQL_PASSWORD' WITH GRANT OPTION;"
	mysql --user="root" --password="$MYSQL_PASSWORD" -e "FLUSH PRIVILEGES;"
	systemctl restart mysql
	echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
	apt-get -y install phpmyadmin
	MYSQL_USERNAME=$USERNAME
	log_only "MariaDB and phpMyAdmin installed."
else
	log_only "Installing MySQL and phpMyAdmin..."
	echo "mysql-server mysql-server/root_password password $MYSQL_PASSWORD" | debconf-set-selections
	echo "mysql-server mysql-server/root_password_again password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/dbconfig-install boolean true" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/app-password-confirm password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/admin-pass password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/mysql/app-pass password $MYSQL_PASSWORD" | debconf-set-selections
	echo "phpmyadmin phpmyadmin/reconfigure-webserver multiselect none" | debconf-set-selections
	apt-get -y install mysql-client mysql-server phpmyadmin
	MYSQL_USERNAME=root
	log_only "MySQL and phpMyAdmin installed."
fi
$APACHE >> $LOG 2>&1
$MCRYPT >> $LOG 2>&1
$IMAP >> $LOG 2>&1
log_only "Enabled mcrypt and imap modules for PHP."

# Install NOSH
mkdir -p $NOSH_DIR
log_only "The NOSH ChartingSystem documents directory has been created."
chown -R $WEB_GROUP.$WEB_USER "$NOSH_DIR"
chmod -R 755 $NOSH_DIR
if ! [ -d "$NOSH_DIR"/scans ]; then
	mkdir "$NOSH_DIR"/scans
	chown -R $WEB_GROUP.$WEB_USER "$NOSH_DIR"/scans
	chmod -R 777 "$NOSH_DIR"/scans
fi
if ! [ -d "$NOSH_DIR"/received ]; then
	mkdir "$NOSH_DIR"/received
	chown -R $WEB_GROUP.$WEB_USER "$NOSH_DIR"/received
fi
if ! [ -d "$NOSH_DIR"/sentfax ]; then
	mkdir "$NOSH_DIR"/sentfax
	chown -R $WEB_GROUP.$WEB_USER "$NOSH_DIR"/sentfax
fi
log_only "The NOSH ChartingSystem scan and fax directories are secured."
log_only "The NOSH ChartingSystem documents directory is secured."
cd $NOSH_DIR
composer create-project nosh2/nosh2 --prefer-dist --stability dev
cd $NEWNOSH

# Create directory file
touch $NOSHDIRFILE
echo "$NOSH_DIR"/ >> $NOSHDIRFILE

# Edit .env file
sed -i '/^DB_DATABASE=/s/=.*/='"${MYSQL_DATABASE}"'/' $NEWCONFIGDATABASE
sed -i '/^DB_USERNAME=/s/=.*/='"${MYSQL_USERNAME}"'/' $NEWCONFIGDATABASE
sed -i '/^DB_PASSWORD=/s/=.*/='"${MYSQL_PASSWORD}"'/' $NEWCONFIGDATABASE

chown -R $WEB_GROUP.$WEB_USER $NEWNOSH
chmod -R 755 $NEWNOSH
chmod -R 777 $NEWNOSH/storage
chmod -R 777 $NEWNOSH/public
chmod 777 $NEWNOSH/noshfax
chmod 777 $NEWNOSH/noshreminder
chmod 777 $NEWNOSH/noshbackup
log_only "Installed NOSH ChartingSystem core files."
echo "create database $MYSQL_DATABASE" | mysql -u $MYSQL_USERNAME -p$MYSQL_PASSWORD
php artisan migrate:install
php artisan migrate
log_only "Installed NOSH ChartingSystem database schema."

if [ -e "$WEB_CONF"/nosh2.conf ]; then
	rm "$WEB_CONF"/nosh2.conf
fi
touch "$WEB_CONF"/nosh2.conf
if [[ ! -z $DOMAIN ]]; then
	SERVERNAME=$DOMAIN
else
	SERVERNAME='localhost'
fi
APACHE_CONF="<VirtualHost _default_:80>
	ServerName $SERVERNAME
	DocumentRoot /var/www/html
	ErrorLog ${APACHE_LOG_DIR}/error.log
	CustomLog ${APACHE_LOG_DIR}/access.log combined
</VirtualHost>
<IfModule mod_ssl.c>
	<VirtualHost _default_:443>
		ServerName $SERVERNAME
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
	AllowOverride None"
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
echo "$APACHE_CONF" >> "$WEB_CONF"/nosh2.conf
log_only "NOSH ChartingSystem Apache configuration file set."
$APACHE >> $LOG 2>&1
log_only "Restarting Apache service."

# Install LetsEncrypt
if [[ ! -z $DOMAIN ]]; then
	cd /usr/local/bin
	wget https://dl.eff.org/certbot-auto
	chmod a+x /usr/local/bin/certbot-auto
	./certbot-auto --apache -d $DOMAIN
fi

# Get IP address if needed
myip=$(ifconfig -a | awk '/(cast)/ {print $2}' | cut -d: -f2)
if [[ -n $myip ]]; then
	for i in $myip; do
		if [[ ! -z $i ]]; then
			target=$(echo $i | cut -d"." -f1-3)
			target1=$target".1"
			count=$( ping -c 1 $target1 | grep ttl_* | wc -l )
			if [ $count -ne 0 ]; then
				DOMAIN_NOSH=$i
			fi
		fi
	done
fi

# Installation completed
log_only "You can now complete your new installation of NOSH ChartingSystem by browsing to:"
if [[ ! -z $DOMAIN ]]; then
	log_only "https://$DOMAIN/nosh"
	log_only "or https://$DOMAIN_NOSH/nosh"
else
	log_only "https://$DOMAIN_NOSH/nosh"
fi
exit 0
