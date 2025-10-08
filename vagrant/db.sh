#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive   # apt не питає підтвердження

# змінні
DB_HOST="${DB_HOST:-192.168.56.10}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-petclinic}"
DB_USER="${DB_USER:-petclinic}"
DB_PASS="${DB_PASS:-petclinic}"
DB_CLIENT_HOST="${DB_CLIENT_HOST:-192.168.56.%}"    # % - будь-яка адреса

# оновлюємо та встановлюємо mssql
echo "update & install mysql"
sudo apt-get update -y
sudo apt-get install -y mysql-server

MYSQLD_CNF="/etc/mysql/mysql.conf.d/mysqld.cnf"

# налаштування ip та порта mysql
echo "mysql - config ip:port"
sudo sed -i "s/^bind-address.*/bind-address = ${DB_HOST}/" "$MYSQLD_CNF" || echo "bind-address = ${DB_HOST}" | sudo tee -a "$MYSQLD_CNF"
sudo sed -i "s/^port.*/port = ${DB_PORT}/" "$MYSQLD_CNF" || echo "port = ${DB_PORT}" | sudo tee -a "$MYSQLD_CNF"

sudo systemctl enable mysql
sudo systemctl restart mysql

# створюємо базу та користувача mysql
echo "mysql create base & user"
sudo mysql <<SQL
CREATE DATABASE IF NOT EXISTS \`${DB_NAME}\` CHARACTER SET utf8mb4 COLLATE utf8mb4_general_ci;
CREATE USER IF NOT EXISTS '${DB_USER}'@'${DB_CLIENT_HOST}' IDENTIFIED BY '${DB_PASS}';
GRANT ALL PRIVILEGES ON \`${DB_NAME}\`.* TO '${DB_USER}'@'${DB_CLIENT_HOST}';
FLUSH PRIVILEGES;
SQL

echo "finish db.sh"