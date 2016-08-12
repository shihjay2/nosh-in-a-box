#!/bin/bash

UBUNTU_VER=$(lsb_release -rs)

if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
	php_config_file="/etc/php/7.0/apache2/php.ini"
else
	php_config_file="/etc/php5/apache2/php.ini"
fi

# This function is called at the very bottom of the file
main() {
	repositories_go
	update_go
	network_go
	tools_go
	apache_go
	php_go
	autoremove_go
}

repositories_go() {
	echo "NOOP"
}

update_go() {
	# Update the server
	apt-get update
	# apt-get -y upgrade
}

autoremove_go() {
	apt-get -y autoremove
}

network_go() {
	IPADDR=$(/sbin/ifconfig eth0 | awk '/inet / { print $2 }' | sed 's/addr://')
	sed -i "s/^${IPADDR}.*//" /etc/hosts
	echo ${IPADDR} ubuntu.localhost >> /etc/hosts			# Just to quiet down some error messages
}

tools_go() {
	# Install basic tools
	apt-get -y install build-essential binutils-doc git subversion bc

	# Run install script at first logon
	echo "sudo bash /vagrant/install.sh" >> /home/ubuntu/.bashrc
	echo 'alias install-ssl="sudo bash /vagrant/ssl.sh"' >> /home/ubuntu/.bashrc
	echo 'alias local-ip="sudo bash /vagrant/localip.sh"' >> /home/ubuntu/.bashrc
	# echo "sudo bash /vagrant/install.sh" >> /home/vagrant/.bashrc
}

apache_go() {
	# Install Apache
	apt-get -y install apache2

	a2enmod rewrite
	a2enmod ssl

	if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
		systemctl restart apache2
	else
		service apache2 reload
		update-rc.d apache2 enable
	fi
}

php_go() {
	if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
		apt-get -y install php php-zip php-curl php-mysql php-pear php-mcrypt php-imap libapache2-mod-php php-gd php-imagick php-gd php-cli php-curl php-common libdbi-perl libdbd-mysql-perl libssh2-1-dev php-ssh2 php-soap imagemagick pdftk openssh-server
	else
		apt-get -y install php5 php5-curl php5-mysql php-pear php5-mcrypt php5-imap libapache2-mod-php5 php5-gd php5-imagick php5-gd php5-cli php5-curl php5-common libdbi-perl libdbd-mysql-perl libssh2-1-dev libssh2-php php-soap imagemagick pdftk openssh-server
	fi
	sed -i "s/display_startup_errors = Off/display_startup_errors = On/g" ${php_config_file}
	sed -i "s/display_errors = Off/display_errors = On/g" ${php_config_file}

	if [[ "$UBUNTU_VER" = 16.04 ]] || [[ "$UBUNTU_VER" > 16.04 ]]; then
		systemctl restart apache2
	else
		service apache2 reload
	fi
	# Install latest version of Composer globally
	if [ ! -f "/usr/local/bin/composer" ]; then
		curl -sS https://getcomposer.org/installer | php -- --install-dir=/usr/local/bin --filename=composer
	fi
}

main
exit 0
