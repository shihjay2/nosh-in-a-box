# NOSH-in-a-Box


## Installation
Go to the [wiki](https://github.com/shihjay2/nosh-in-a-box/wiki/Installation) for details.

## Dependencies
1. [VirtualBox](https://www.virtualbox.org)
2. [Vagrant](https://www.vagrantup.com)
3. An SSH client (to connect to NOSH-in-a-Box)

## Important built-in scripts
1. <code>install-ssl</code> - Script to register an SSL certificate for free through [Let's Encrypt](https://letsencrypt.org)
2. <code>local-ip</code> - Script to show the local IP address that NOSH-in-a-Box can be accessed to from within your local area network (if not deployed into the cloud).  This number is important to use if you plan to configure your network router and assign port forwarding to this IP address (ports 22, 80, and 443 should be open)

## How to call the scripts
With your terminal application, go to the directory where your Vagrantfile is located for NOSH-in-a-Box, activate the box (if needed), and SSH into it.

	cd /home/Me/nosh
	vagrant up
	vagrant ssh

Just type in the above commands at any point in the command line

	ubuntu@ubuntu_xenial:~$ install-ssl

## Security Vulnerabilities

If you discover a security vulnerability within NOSH-in-a-Box, please send an e-mail to Michael Chen at shihjay2 at gmail.com. All security vulnerabilities will be promptly addressed.

## License

NOSH-in-a-Box is open-sourced software licensed under the [GNU AGPLv3 license](https://opensource.org/licenses/AGPL-3.0).
