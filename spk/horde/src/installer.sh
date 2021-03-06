#!/bin/sh

# Package
PACKAGE="horde"
DNAME="Horde"

# Others
INSTALL_DIR="/usr/local/${PACKAGE}"
SSS="/var/packages/${PACKAGE}/scripts/start-stop-status" 
WEB_DIR="/var/services/web"
USER="$([ $(grep buildnumber /etc.defaults/VERSION | cut -d"\"" -f2) -ge 4418 ] && echo -n http || echo -n nobody)"
MYSQL="/usr/syno/mysql/bin/mysql"
MYSQL_USER="horde"
MYSQL_DATABASE="horde"
TMP_DIR="${SYNOPKG_PKGDEST}/../../@tmp"


preinst ()
{
    # Check database
    if [ "${SYNOPKG_PKG_STATUS}" == "INSTALL" ]; then
        if ! ${MYSQL} -u root -p"${wizard_mysql_password_root}" -e quit > /dev/null 2>&1; then
            echo "Incorrect MySQL root password"
            exit 1
        fi
        if ${MYSQL} -u root -p"${wizard_mysql_password_root}" mysql -e "SELECT User FROM user" | grep ^${MYSQL_USER}$ > /dev/null 2>&1; then
            echo "MySQL user ${MYSQL_USER} already exists"
            exit 1
        fi
        if ${MYSQL} -u root -p"${wizard_mysql_password_root}" -e "SHOW DATABASES" | grep ^${MYSQL_DATABASE}$ > /dev/null 2>&1; then
            echo "MySQL database ${MYSQL_DATABASE} already exists"
            exit 1
        fi
    fi

    exit 0
}

postinst ()
{
    # Link
    ln -s ${SYNOPKG_PKGDEST} ${INSTALL_DIR}

    # Install busybox stuff
    ${INSTALL_DIR}/bin/busybox --install ${INSTALL_DIR}/bin

    # Create the web interface
    mkdir ${WEB_DIR}/${PACKAGE}

    # Setup database
    if [ "${SYNOPKG_PKG_STATUS}" == "INSTALL" ]; then
        ${MYSQL} -u root -p"${wizard_mysql_password_root}" -e "CREATE DATABASE ${MYSQL_DATABASE}; GRANT ALL PRIVILEGES ON ${MYSQL_DATABASE}.* TO '${MYSQL_USER}'@'localhost' IDENTIFIED BY '${wizard_mysql_password_horde:=horde}';"
    fi

    # Configure Apache variables
    echo -e "<Directory \"${WEB_DIR}/${PACKAGE}\">\nSetEnv PHP_PEAR_SYSCONF_DIR ${INSTALL_DIR}/etc\nphp_value include_path \".:${INSTALL_DIR}/share/pear\"\nphp_admin_value open_basedir none\n</Directory>" > /usr/syno/etc/sites-enabled-user/${PACKAGE}.conf

    # Create Pear config
    ${INSTALL_DIR}/bin/pear config-create ${INSTALL_DIR}/share ${INSTALL_DIR}/etc/pear.conf > /dev/null

    # Make sure all variables point to correct locations
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set bin_dir ${INSTALL_DIR}/bin > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set doc_dir ${INSTALL_DIR}/var/doc > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set ext_dir ${INSTALL_DIR}/var/ext > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set php_dir ${INSTALL_DIR}/share/pear > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set cache_dir ${INSTALL_DIR}/var/cache > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set cfg_dir ${INSTALL_DIR}/etc > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set data_dir ${INSTALL_DIR}/data > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set download_dir ${INSTALL_DIR}/var/download > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set php_bin /usr/bin/php > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set temp_dir ${INSTALL_DIR}/var/temp > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set test_dir ${INSTALL_DIR}/var/test > /dev/null

    # Begin installation
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf channel-discover pear.horde.org > /dev/null
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf install horde/horde_role > /dev/null

    # Create required Horde variable manually instead of running interactive script via "run-scripts horde/horde_role"
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf config-set -c pear.horde.org horde_dir ${WEB_DIR}/${PACKAGE} > /dev/null

    # Setup temporary page
    echo -e "<html><body><h2>Horde installation is in progress, please wait. It can take 10 to 20 minutes to finish.</h2></body></html>" \
      > ${WEB_DIR}/${PACKAGE}/index.html

    # Save selected edition because of upgrades
    if [ "${SYNOPKG_PKG_STATUS}" == "INSTALL" ]; then
        if [ ${wizard_horde_edition_groupware} == "true" ]; then
            echo "groupware" > ${INSTALL_DIR}/var/edition
        else
            echo "webmail" > ${INSTALL_DIR}/var/edition
        fi
    else
        mv ${TMP_DIR}/${PACKAGE}/edition ${INSTALL_DIR}/var
    fi

    edition=`cat ${INSTALL_DIR}/var/edition`

    # Finish installation in the background
    postinst_bg &

    exit 0
}

postinst_bg ()
{
    ${INSTALL_DIR}/bin/pear -c ${INSTALL_DIR}/etc/pear.conf install -a -B -f horde/$edition > $(INSTALL_DIR)/var/install.log 2>&1

    if [ "${SYNOPKG_PKG_STATUS}" == "INSTALL" ]; then
        cp ${WEB_DIR}/${PACKAGE}/config/conf.php.dist ${WEB_DIR}/${PACKAGE}/config/conf.php
        echo -e "\n\$conf['sql']['username'] = '${MYSQL_USER}';" \
          "\n\$conf['sql']['password'] = '${wizard_mysql_password_horde:=horde}';" \
          "\n\$conf['sql']['hostspec'] = 'localhost';" \
          "\n\$conf['sql']['port'] = 3306;" \
          "\n\$conf['sql']['protocol'] = 'tcp';" \
          "\n\$conf['sql']['database'] = '${MYSQL_DATABASE}';" \
          "\n\$conf['sql']['phptype'] = 'mysql';" \
          "\n\$conf['share']['driver'] = 'Sqlng';" \
          "\n\$conf['group']['driver'] = 'Sql';" >> ${WEB_DIR}/${PACKAGE}/config/conf.php
    fi

    # Fix permissions
    chmod -R 777 ${WEB_DIR}/${PACKAGE}

    # Create/update database tables (second run creates last two table)
    PHP_PEAR_SYSCONF_DIR=${INSTALL_DIR}/etc php -d open_basedir=none -d include_path=${INSTALL_DIR}/share/pear ${INSTALL_DIR}/bin/horde-db-migrate >> $(INSTALL_DIR)/var/install.log 2>&1
    PHP_PEAR_SYSCONF_DIR=${INSTALL_DIR}/etc php -d open_basedir=none -d include_path=${INSTALL_DIR}/share/pear ${INSTALL_DIR}/bin/horde-db-migrate >> $(INSTALL_DIR)/var/install.log 2>&1

    # Remove temporary page
    rm ${WEB_DIR}/${PACKAGE}/index.html
}

preuninst ()
{
    # Check database
    if [ "${SYNOPKG_PKG_STATUS}" == "UNINSTALL" -a "${wizard_remove_database}" == "true" ] && ! ${MYSQL} -u root -p"${wizard_mysql_password_root}" -e quit > /dev/null 2>&1; then
        echo "Incorrect MySQL root password"
        exit 1
    fi

    # Stop the package
    ${SSS} stop > /dev/null

    exit 0
}

postuninst ()
{
    # Remove link
    rm -f ${INSTALL_DIR}

    # Remove database
    if [ "${SYNOPKG_PKG_STATUS}" == "UNINSTALL" -a "${wizard_remove_database}" == "true" ]; then
        ${MYSQL} -u root -p"${wizard_mysql_password_root}" -e "DROP DATABASE ${MYSQL_DATABASE}; DROP USER '${MYSQL_USER}'@'localhost';"
    fi

    # Remove Apache configuration
    rm /usr/syno/etc/sites-enabled-user/${PACKAGE}.conf

    # Remove the web interface
    rm -fr ${WEB_DIR}/${PACKAGE}

    exit 0
}

preupgrade ()
{
    # Stop the package
    ${SSS} stop > /dev/null 

    # Save configuration files
    rm -fr ${TMP_DIR}/${PACKAGE}
    mkdir -p ${TMP_DIR}/${PACKAGE}

    # Save package edition config
    mv ${INSTALL_DIR}/var/edition ${TMP_DIR}/${PACKAGE}

    # Save main Horde config
    mv ${WEB_DIR}/${PACKAGE}/config/conf.php ${TMP_DIR}/${PACKAGE}/

    # Save other apps configs
    cd ${WEB_DIR}/${PACKAGE} && for file in */config/conf.php; do
        if [ ! -f ${WEB_DIR}/${PACKAGE}/$file ]; then 
            continue
        fi
        dir=$(dirname $file)
        mkdir -p ${TMP_DIR}/${PACKAGE}/$dir
        mv ${WEB_DIR}/${PACKAGE}/$file ${TMP_DIR}/${PACKAGE}/$file
    done

    exit 0
}

postupgrade ()
{
    # Restore main Horde config
    mkdir -p ${WEB_DIR}/${PACKAGE}/config
    mv ${TMP_DIR}/${PACKAGE}/conf.php ${WEB_DIR}/${PACKAGE}/config/conf.php

    # Restore other apps configs
    cd ${TMP_DIR}/${PACKAGE} && for file in */config/conf.php; do
        if [ ! -f ${TMP_DIR}/${PACKAGE}/$file ]; then 
            continue
        fi
        dir=$(dirname $file)
        mkdir -p ${WEB_DIR}/${PACKAGE}/$dir
        mv ${TMP_DIR}/${PACKAGE}/$file ${WEB_DIR}/${PACKAGE}/$file
    done

    rm -fr ${TMP_DIR}/${PACKAGE}

    exit 0
}
