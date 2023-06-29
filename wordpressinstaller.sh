#!/bin/bash

# This script requires root access, apache2, wget, unzip, and mariadb
# This script is for Ubuntu/Debian systems.

# Checking if user is root
if [ "$(id -u)" != "0" ]; then
   echo "This script must be run as root" 1>&2
   exit 1
fi

# Check if the correct parameters are passed
if [ -z "$1" ]; then
    echo "You must provide a virtual host as the first argument."
    exit 1
fi

if [ -z "$2" ]; then
    echo "You must provide a plugin URL as the second argument."
    exit 1
fi

if [ -z "$3" ]; then
    echo "You must provide a database name as the third argument."
    exit 1
fi

VIRTUAL_HOST=$1
PLUGIN_URL=$2
DB_NAME=$3

DB_USER=wordpress_user
DB_PASSWORD=wordpress_password

# Check if Apache is installed, if not install it.
if ! [ -x "$(command -v apache2)" ]; then
  echo 'Error: Apache2 is not installed.' >&2
  apt-get update
  apt-get install apache2
fi

# Check if MariaDB is installed, if not install it.
if ! [ -x "$(command -v mariadb)" ]; then
  echo 'Error: MariaDB is not installed.' >&2
  apt-get update
  apt-get install mariadb-server
fi

# Create MariaDB Database and User for WordPress
mysql -u root <<EOF
CREATE DATABASE IF NOT EXISTS $DB_NAME;
DROP USER IF EXISTS '$DB_USER'@'localhost';
CREATE USER '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASSWORD';
GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost';
FLUSH PRIVILEGES;
EOF

# Download and extract Wordpress
wget https://wordpress.org/latest.tar.gz
tar -xvf latest.tar.gz

# Moving WordPress to the apache directory
mv wordpress /var/www/$VIRTUAL_HOST

# Creating Apache Virtual Host
cat <<EOF > /etc/apache2/sites-available/$VIRTUAL_HOST.conf
<VirtualHost *:80>
    ServerName $VIRTUAL_HOST
    ServerAlias www.$VIRTUAL_HOST
    DocumentRoot /var/www/$VIRTUAL_HOST
    <Directory /var/www/$VIRTUAL_HOST/>
        AllowOverride All
    </Directory>
</VirtualHost>
EOF

# Enable Virtual Host
a2ensite $VIRTUAL_HOST
systemctl reload apache2

# Add entry to hosts file
echo "127.0.0.1    $VIRTUAL_HOST" >> /etc/hosts

# Download and install plugin
wget $PLUGIN_URL -P /tmp
unzip /tmp/$(basename $PLUGIN_URL) -d /var/www/$VIRTUAL_HOST/wp-content/plugins/

# Configuring WordPress
cat <<EOF > /var/www/$VIRTUAL_HOST/wp-config.php
<?php
define( 'DB_NAME', '$DB_NAME' );
define( 'DB_USER', '$DB_USER' );
define( 'DB_PASSWORD', '$DB_PASSWORD' );
define( 'DB_HOST', 'localhost' );
define( 'DB_CHARSET', 'utf8' );
define( 'DB_COLLATE', '' );
EOF

wget -q -O - https://api.wordpress.org/secret-key/1.1/salt/ >> /var/www/$VIRTUAL_HOST/wp-config.php

cat <<EOF >> /var/www/$VIRTUAL_HOST/wp-config.php
\$table_prefix = 'wp_';
define( 'WP_DEBUG', false );
if ( ! defined( 'ABSPATH' ) ) {
	define( 'ABSPATH', __DIR__ . '/' );
}
require_once( ABSPATH . 'wp-settings.php' );
EOF

chown -R www-data:www-data /var/www/$VIRTUAL_HOST

# Restart services
systemctl restart apache2
systemctl restart mariadb

echo "All done, WordPress should be up and running now."
