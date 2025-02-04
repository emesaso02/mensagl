#!/bin/bash

echo "🚀 Iniciando despliegue de infraestructura en AWS..."

# =======================
# 📌 VARIABLES GLOBALES
# =======================
KEY_NAME="ssh-mensagl-2025-Equipo6"
VPC_NAME="VPC-mensagl-2025-Equipo6"
DB_SUBNET_GROUP_NAME="subnet-group-mensagl"
RDS_INSTANCE_ID="mysql-db-mensagl-2025"
REGION="us-east-1"
AMI_ID="ami-04b4f1a9cf54c11d0"  # La imágen de Ubuntu Server 24.04 en us-east-1

# =======================
# 📌 1. Creación de Claves SSH
# =======================
echo "🔑 Creando clave SSH..."
aws ec2 create-key-pair --key-name $KEY_NAME --query 'KeyMaterial' --output text > $KEY_NAME.pem
chmod 400 $KEY_NAME.pem

# =======================
# 📌 2. Creación de VPC y Subredes en 2 AZs
# =======================
echo "🌐 Creando VPC y Subredes en 2 zonas de disponibilidad..."
VPC_ID=$(aws ec2 create-vpc --cidr-block 10.221.0.0/16 --query 'Vpc.VpcId' --output text)
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-support
aws ec2 modify-vpc-attribute --vpc-id $VPC_ID --enable-dns-hostnames

# Asignamos nombre a la VPC
aws ec2 create-tags --resources $VPC_ID --tags Key=Name,Value="VPC-Mensagl-2025-Equipo6"

# Las subredes en 2 AZs
SUBNET_PUBLIC1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.221.1.0/24 --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
SUBNET_PUBLIC2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.221.2.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)

SUBNET_PRIVATE1_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.221.3.0/24 --availability-zone ${REGION}a --query 'Subnet.SubnetId' --output text)
SUBNET_PRIVATE2_ID=$(aws ec2 create-subnet --vpc-id $VPC_ID --cidr-block 10.221.4.0/24 --availability-zone ${REGION}b --query 'Subnet.SubnetId' --output text)

# Asignamos nombres a las subredes
aws ec2 create-tags --resources $SUBNET_PUBLIC1_ID --tags Key=Name,Value="Subnet-Publica-1"
aws ec2 create-tags --resources $SUBNET_PUBLIC2_ID --tags Key=Name,Value="Subnet-Publica-2"
aws ec2 create-tags --resources $SUBNET_PRIVATE1_ID --tags Key=Name,Value="Subnet-Privada-1"
aws ec2 create-tags --resources $SUBNET_PRIVATE2_ID --tags Key=Name,Value="Subnet-Privada-2"

echo "✅ Subredes creadas: "
echo "   - Pública 1: $SUBNET_PUBLIC1_ID"
echo "   - Pública 2: $SUBNET_PUBLIC2_ID"
echo "   - Privada 1: $SUBNET_PRIVATE1_ID"
echo "   - Privada 2: $SUBNET_PRIVATE2_ID"

# =======================
# 📌 3. Crear Gateway de Internet y NAT
# =======================
echo "🌍 Configurando Gateway de Internet y NAT..."
IGW_ID=$(aws ec2 create-internet-gateway --query 'InternetGateway.InternetGatewayId' --output text)
aws ec2 attach-internet-gateway --vpc-id $VPC_ID --internet-gateway-id $IGW_ID

# =======================
# 📌 4. Crear Grupos de Seguridad
# =======================
echo "🔒 Creando Grupos de Seguridad..."
SG_PROXY_ID=$(aws ec2 create-security-group --group-name SG-Proxy --description "Proxy Nginx" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_XMPP_ID=$(aws ec2 create-security-group --group-name SG-XMPP --description "XMPP ejabberd" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_PGSQL_ID=$(aws ec2 create-security-group --group-name SG-PostgreSQL --description "PostgreSQL en EC2" --vpc-id $VPC_ID --query 'GroupId' --output text)
SG_RDS_ID=$(aws ec2 create-security-group --group-name SG-RDS --description "RDS MySQL" --vpc-id $VPC_ID --query 'GroupId' --output text)

# 📌 Reglas para SG-Proxy (Acceso público HTTP, HTTPS, SSH)
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 80 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 443 --cidr 0.0.0.0/0
aws ec2 authorize-security-group-ingress --group-id $SG_PROXY_ID --protocol tcp --port 22 --cidr 0.0.0.0/0

# 📌 Reglas para SG-XMPP (Permitir solo desde la VPC)
aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 5222 --source-group $SG_XMPP_ID
aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 5269 --source-group $SG_XMPP_ID
aws ec2 authorize-security-group-ingress --group-id $SG_XMPP_ID --protocol tcp --port 22 --source-group $SG_PROXY_ID

# 📌 Reglas para SG-PostgreSQL (Acceso desde XMPP y Soporte)
aws ec2 authorize-security-group-ingress --group-id $SG_PGSQL_ID --protocol tcp --port 5432 --source-group $SG_XMPP_ID
aws ec2 authorize-security-group-ingress --group-id $SG_PGSQL_ID --protocol tcp --port 5432 --source-group $SG_PROXY_ID

# 📌 Reglas para SG-RDS (Acceso desde WordPress y Soporte)
aws ec2 authorize-security-group-ingress --group-id $SG_RDS_ID --protocol tcp --port 3306 --source-group $SG_PROXY_ID

# =======================
# 📌 5. Crear Instancias EC2 con IP FIJA
# =======================
echo "🖥️ Creando instancias EC2 con IP fija..."

# Proxy Nginx 1 y 2 (IP Pública asignada)
INSTANCE_PROXY1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PUBLIC1_ID --private-ip-address 10.221.1.10 --security-group-ids $SG_PROXY_ID --associate-public-ip-address --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_PROXY1_ID --tags Key=Name,Value="Proxyinverso1"

INSTANCE_PROXY2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PUBLIC2_ID --private-ip-address 10.221.2.10 --security-group-ids $SG_PROXY_ID --associate-public-ip-address --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_PROXY2_ID --tags Key=Name,Value="Proxyinverso2"

# XMPP Servers (Mensajería 1 y 2)
INSTANCE_XMPP1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE1_ID --private-ip-address 10.221.3.10 --security-group-ids $SG_XMPP_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_XMPP1_ID --tags Key=Name,Value="Mensajeria1"

INSTANCE_XMPP2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE1_ID --private-ip-address 10.221.3.20 --security-group-ids $SG_XMPP_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_XMPP2_ID --tags Key=Name,Value="Mensajeria2"

# PostgreSQL DB Server
INSTANCE_PGSQL_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE1_ID --private-ip-address 10.221.3.30 --security-group-ids $SG_PGSQL_ID --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_PGSQL_ID --tags Key=Name,Value="Postgresql"

# Servidores de Soporte 1 y 2
INSTANCE_SOPORTE1_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE2_ID --private-ip-address 10.221.4.10 --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_SOPORTE1_ID --tags Key=Name,Value="Soporte1"

INSTANCE_SOPORTE2_ID=$(aws ec2 run-instances --image-id $AMI_ID --instance-type t2.micro --key-name $KEY_NAME --subnet-id $SUBNET_PRIVATE2_ID --private-ip-address 10.221.4.20 --query 'Instances[0].InstanceId' --output text)
aws ec2 create-tags --resources $INSTANCE_SOPORTE2_ID --tags Key=Name,Value="Soporte2"

# =======================
# 📌 CREAR GRUPO DE SUBREDES PARA RDS
# =======================
echo "💾 Creando grupo de subredes para RDS MySQL..."

aws rds create-db-subnet-group \
    --db-subnet-group-name "cms-db-subnet-group" \
    --db-subnet-group-description "Grupo de subredes para RDS MySQL CMS" \
    --subnet-ids $SUBNET_PRIVATE1_ID $SUBNET_PRIVATE2_ID \
    --tags Key=Name,Value="cms-db-subnet-group"

echo "✅ Grupo de subredes creado exitosamente."

# =======================
# 📌 CREAR INSTANCIA RDS MYSQL
# =======================
echo "💾 Creando instancia de RDS MySQL..."

aws rds create-db-instance \
    --db-instance-identifier "cms-database" \
    --allocated-storage 20 \
    --storage-type "gp2" \
    --db-instance-class "db.t3.micro" \
    --engine "mysql" \
    --engine-version "8.0" \
    --master-username "admin" \
    --master-user-password "Admin123" \
    --db-name "wordpress_db" \
    --db-subnet-group-name "cms-db-subnet-group" \
    --vpc-security-group-ids "$SG_RDS_ID" \
    --publicly-accessible \
    --tags Key=Name,Value="wordpress_db"


echo "✅ Instancia RDS MySQL creada exitosamente."
