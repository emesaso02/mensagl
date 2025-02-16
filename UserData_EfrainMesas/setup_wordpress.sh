#!/bin/bash

# Script de instalación de WordPress con WP-CLI
# Autor: Efraín Mesas
# Versión: 1.1

# Variables de configuración
WP_PATH="/var/www/html"
DB_NAME="wordpress_db"
DB_USER="admin"
DB_HOST="cms-database.czynv315xvfs.us-east-1.rds.amazonaws.com"
SITE_URL="http://wordpress-efrain.duckdns.org"
SITE_TITLE="Soporte"
ADMIN_USER="admin"
PLUGIN_LIST=("supportcandy" "user-registration" "wps-hide-login")

# Solicitar credenciales de forma segura
read -s -p "Ingrese la contraseña del usuario de la base de datos: " DB_PASS
echo ""
read -s -p "Ingrese la contraseña para el usuario administrador de WordPress: " ADMIN_PASS
echo ""

# Función para verificar si un comando se ejecutó correctamente
check_success() {
    if [ $? -ne 0 ]; then
        echo "Error en la ejecución. Saliendo..."
        exit 1
    fi
}

# Instalar dependencias necesarias
echo "Instalando dependencias..."
sudo DEBIAN_FRONTEND=noninteractive apt install -y apache2 curl rsync git unzip ghostscript libapache2-mod-php mysql-server php php-bcmath php-curl php-imagick php-intl php-json php-mbstring php-mysql php-xml
check_success

# Descargar e instalar WP-CLI
echo "Instalando WP-CLI..."
curl -O https://raw.githubusercontent.com/wp-cli/builds/gh-pages/phar/wp-cli.phar
check_success
chmod +x wp-cli.phar
sudo mv wp-cli.phar /usr/local/bin/wp-cli
check_success

# Limpiar el directorio de WordPress
echo "Limpiando el directorio de instalación..."
sudo rm -rf $WP_PATH/*
sudo chmod -R 755 $WP_PATH
sudo chown -R www-data:www-data $WP_PATH
check_success

# Reiniciar Apache
echo "Reiniciando Apache..."
sudo a2enmod rewrite
sudo systemctl restart apache2
check_success

# Descargar WordPress
echo "Descargando WordPress..."
sudo -u www-data wp-cli core download --path="$WP_PATH"
check_success

# Configurar WordPress
echo "Configurando WordPress..."
sudo -u www-data wp-cli core config --dbname="$DB_NAME" --dbuser="$DB_USER" --dbpass="$DB_PASS" --dbhost="$DB_HOST" --dbprefix=wp_ --path="$WP_PATH"
check_success

# Instalar WordPress
echo "Instalando WordPress..."
sudo -u www-data wp-cli core install --url="$SITE_URL" --title="$SITE_TITLE" --admin_user="$ADMIN_USER" --admin_password="$ADMIN_PASS" --admin_email="emesaso02@educantabria.es" --path="$WP_PATH"
check_success

# Instalar y activar plugins
echo "Instalando plugins..."
for plugin in "${PLUGIN_LIST[@]}"; do
    sudo -u www-data wp-cli plugin install $plugin --activate --path="$WP_PATH"
    check_success
done

# Configurar WPS Hide Login
sudo -u www-data wp-cli option update wps_hide_login_url admin-ivan --path="$WP_PATH"
check_success

# Configurar permisos de usuario
echo "Configurando permisos para suscriptores..."
sudo -u www-data wp-cli cap add "subscriber" "read" --path="$WP_PATH"
sudo -u www-data wp-cli cap add "subscriber" "create_ticket" --path="$WP_PATH"
sudo -u www-data wp-cli cap add "subscriber" "view_own_ticket" --path="$WP_PATH"
sudo -u www-data wp-cli option update default_role "subscriber" --path="$WP_PATH"
check_success

# Permitir registro de usuarios
echo "Habilitando registro de usuarios..."
sudo -u www-data wp-cli option update users_can_register 1 --path="$WP_PATH"
check_success

# Crear páginas necesarias
echo "Creando páginas..."
sudo -u www-data wp-cli post create --post_title="Mi cuenta" --post_content="[user_registration_my_account]" --post_status="publish" --post_type="page" --path="$WP_PATH" --porcelain
sudo -u www-data wp-cli post create --post_title="Registro" --post_content="[user_registration_form id='9']" --post_status="publish" --post_type="page" --path="$WP_PATH" --porcelain
sudo -u www-data wp-cli post create --post_title="Tickets" --post_content="[supportcandy]" --post_status="publish" --post_type="page" --path="$WP_PATH" --porcelain
check_success

# Modificar wp-config.php para proxies inversos
echo "Modificando configuración de WordPress para proxies inversos..."
sudo sed -i '1d' $WP_PATH/wp-config.php
sudo sed -i '1i\
<?php if (isset($_SERVER["HTTP_X_FORWARDED_FOR"])) {\
    $list = explode(",", $_SERVER["HTTP_X_FORWARDED_FOR"]);\
    $_SERVER["REMOTE_ADDR"] = $list[0];\
}\
$_SERVER["HTTP_HOST"] = "'"$SITE_URL"'";\
$_SERVER["REMOTE_ADDR"] = "'"$SITE_URL"'";\
$_SERVER["SERVER_ADDR"] = "'"$SITE_URL"'";\
' $WP_PATH/wp-config.php
check_success

echo "WordPress ha sido instalado correctamente."
