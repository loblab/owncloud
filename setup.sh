#!/bin/bash
# Copyright 2017 loblab
# 
# Licensed under the Apache License, Version 2.0 (the "License");
# you may not use this file except in compliance with the License.
# You may obtain a copy of the License at
# 
#       http://www.apache.org/licenses/LICENSE-2.0
# 
# Unless required by applicable law or agreed to in writing, software
# distributed under the License is distributed on an "AS IS" BASIS,
# WITHOUT WARRANTIES OR CONDITIONS OF ANY KIND, either express or implied.
# See the License for the specific language governing permissions and
# limitations under the License.

set -e
PROG_DIR=$(dirname $0)

function log_msg() {
  echo $(date +'%m/%d %H:%M:%S') - $*
}

function install_system_packages() {
    codename=$(lsb_release -cs)

    log_msg "Install database server..."
    export DEBIAN_FRONTEND=noninteractive
    sudo -E apt-get -y install mysql-server
    sudo apt-get -y install mysql-client

    log_msg "Install Apache..."
    sudo apt-get -y install apache2 libapache2-mod-php

    log_msg "Install PHP..."
    if [ "$codename" == "jessie" ]; then
        sudo apt-get -y install php5-fpm php5-mysql php5-gd
    else
        sudo apt-get -y install php-fpm php-mysql php-gd php-json php-curl 
        sudo apt-get -y install php-intl php-mcrypt php-imagick
        sudo apt-get -y install php-xml php-mbstring php-zip
    fi
}

function setup_database() {
    log_msg "Setup database..."
    sudo mysql -e "CREATE DATABASE IF NOT EXISTS $DB_NAME;" 
    sudo mysql -e "GRANT ALL PRIVILEGES ON mysql.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"
    sudo mysql -e "GRANT ALL PRIVILEGES ON $DB_NAME.* TO '$DB_USER'@'localhost' IDENTIFIED BY '$DB_PASS' WITH GRANT OPTION;"
    sudo mysql -e "FLUSH PRIVILEGES;"
}

function setup_apache_config() {
    log_msg "Setup Apache config file..."
    cfgfile=/etc/apache2/sites-available/owncloud.conf
    cat $PROG_DIR/apache.conf | 
        perl -pe "s#Alias\s+/owncloud#Alias /$URL_ALIAS#" |
        perl -pe "s#/var/www/owncloud#$WWW_DIR#" |
        sudo tee $cfgfile
    sudo a2ensite owncloud
}

function setup_apache() {
    sudo a2enmod rewrite
    sudo a2enmod headers
    sudo a2enmod env
    sudo a2enmod dir
    sudo a2enmod mime
    setup_apache_config
    sudo service apache2 restart
}

function download_owncloud() {
    TMPFILE=/tmp/owncloud-$VER.tar.bz2
    if ! [ -f $TMPFILE ]; then
        log_msg "Download ownCloud files..."
        wget -O $TMPFILE https://download.owncloud.org/community/owncloud-$VER.tar.bz2 
    fi
    sudo mkdir -p $WWW_DIR
    log_msg "Extract $TMPFILE to $WWW_DIR..."
    sudo tar -xjvf $TMPFILE -C $WWW_DIR --strip-components=1 > /dev/null
    sudo chown -R www-data:www-data $WWW_DIR
    #rm $TMPFILE
}

function install_owncloud() {
    log_msg "Install ownCloud..."
    sudo mkdir -p $DATA_DIR
    sudo chown www-data:www-data $DATA_DIR
    cd $WWW_DIR
    sudo -u www-data php occ maintenance:install \
        --database "mysql" --database-name "$DB_NAME" \
        --database-user "$DB_USER" --database-pass "$DB_PASS" \
        --admin-user "$ADMIN_USER" --admin-pass "$ADMIN_PASS" \
        --data-dir $DATA_DIR
}

function add_trusted_domain() {
    domain=$1
    cfgfile=$WWW_DIR/config/config.php
    log_msg "Add '$domain' to trusted domain (check $cfgfile)..."
    sudo sed "/0 => 'localhost'/ a \ \ \ \ 10 => '$domain'," -i $cfgfile
}

function setup_install() {
    install_system_packages
    setup_database
    setup_apache
    download_owncloud
    install_owncloud
    addr=$(hostname -I | sed 's/ //g')
    add_trusted_domain $addr
    log_msg "Succeeded. Please access http://$addr/$URL_ALIAS/ ($ADMIN_USER/$ADMIN_PASS)"
}

function setup_uninstall() {
    if [ -d $WWW_DIR ]; then
        log_msg "Remove directory $WWW_DIR..."
        sudo rm -rf $WWW_DIR
    fi

    log_msg "Clean database..."
    sudo mysql -e "DROP DATABASE IF EXISTS $DB_NAME;" 
}

function main {
    source $PROG_DIR/config.rc
    if [ -z "$1" ]; then
        setup_install
    else
        for arg in $*
        do
            setup_$arg
        done
    fi
}

main $*
