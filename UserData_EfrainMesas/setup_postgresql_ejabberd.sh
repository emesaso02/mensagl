#!/bin/bash

# Script de instalación de PostgreSQL para XMPP (Ejabberd)
# Autor: Efraín Mesas
# Versión: 1.1

# Configuración
PG_VERSION="14"
DB_NAME="ejabberd_db"
DB_USER="ejabberd_efrain"

# Solicitar contraseña de forma segura
read -s -p "Ingrese la contraseña para el usuario de la base de datos: " DB_PASS
echo ""

# Función para verificar si un comando se ejecutó correctamente
check_success() {
    if [ $? -ne 0 ]; then
        echo "Error en la ejecución. Saliendo..."
        exit 1
    fi
}

# Actualizar e instalar PostgreSQL
echo "Actualizando sistema..."
sudo apt update -y && sudo apt upgrade -y
check_success

echo "Instalando PostgreSQL $PG_VERSION..."
sudo apt install -y postgresql-$PG_VERSION postgresql-contrib
check_success

# Habilitar y arrancar PostgreSQL
echo "Habilitando y arrancando PostgreSQL..."
sudo systemctl enable postgresql
sudo systemctl start postgresql
check_success

# Configurar la base de datos de Ejabberd
echo "Configurando la base de datos para Ejabberd..."
sudo -u postgres psql <<EOF
DO \$\$ 
BEGIN
    IF NOT EXISTS (SELECT FROM pg_roles WHERE rolname = '$DB_USER') THEN
        CREATE USER $DB_USER WITH PASSWORD '$DB_PASS';
    END IF;
    IF NOT EXISTS (SELECT FROM pg_database WHERE datname = '$DB_NAME') THEN
        CREATE DATABASE $DB_NAME OWNER $DB_USER;
    END IF;
    GRANT ALL PRIVILEGES ON DATABASE $DB_NAME TO $DB_USER;
END \$\$;
EOF
check_success

# Configurar acceso remoto
echo "Configurando acceso remoto..."
PG_HBA="/etc/postgresql/$PG_VERSION/main/pg_hba.conf"
POSTGRESQL_CONF="/etc/postgresql/$PG_VERSION/main/postgresql.conf"

sudo sed -i "s/^#listen_addresses = 'localhost'/listen_addresses = '*'/" $POSTGRESQL_CONF
echo "host    $DB_NAME    $DB_USER    0.0.0.0/0    md5" | sudo tee -a $PG_HBA > /dev/null
check_success

# Reiniciar PostgreSQL para aplicar cambios
echo "Reiniciando PostgreSQL..."
sudo systemctl restart postgresql
check_success

echo "PostgreSQL ha sido configurado correctamente para Ejabberd."
