#!/usr/bin/env bash
set -euo pipefail

export DEBIAN_FRONTEND=noninteractive  # щоб apt не питав підтвердження

# змінні для app
APP_USER="${APP_USER:-appuser}"
PROJECT_REPO="${PROJECT_REPO:-https://github.com/allex-git/step1_petClinic.git}"
PROJECT_SUBDIR="${PROJECT_SUBDIR:-}"

# якщо project_dir/app_dir не задані у vars.yml ---> ставимо дефолти
PROJECT_DIR="${PROJECT_DIR:-/home/${APP_USER}/petclinic}"
APP_DIR="${APP_DIR:-/home/${APP_USER}}"

# змінні для db
DB_HOST="${DB_HOST:-192.168.56.10}"
DB_PORT="${DB_PORT:-3306}"
DB_NAME="${DB_NAME:-petclinic}"
DB_USER="${DB_USER:-petclinic}"
DB_PASS="${DB_PASS:-petclinic}"

# оновлюємо та встановлюємо потрібні пакети
echo "update & install packege"
sudo apt-get update -y
sudo apt-get install -y openjdk-11-jdk git unzip curl mysql-client

# створюємо користувача APP_USER (якщо вістуній)
if ! id -u "${APP_USER}" >/dev/null 2>&1; then
  echo "create user for PetClinic"
  sudo adduser --disabled-password --gecos "" "${APP_USER}"
fi

# створюємо каталог проекту та налаштовуємо під appuser
echo "create dir for PetClinic"
sudo mkdir -p "${PROJECT_DIR}"
sudo chown -R "${APP_USER}:${APP_USER}" "${PROJECT_DIR}"

echo "сloning repo PetClinic"
if [ ! -d "${PROJECT_DIR}/.git" ]; then
  sudo -u "${APP_USER}" git clone --depth 1 "${PROJECT_REPO}" "${PROJECT_DIR}"
else
  sudo -u "${APP_USER}" git -C "${PROJECT_DIR}" pull --rebase || true
fi

echo "finish сloning repo PetClinic"

# перевірка, що власник каталогів appuser
sudo chown -R "${APP_USER}:${APP_USER}" "${PROJECT_DIR}"

# якщо проект у підкаталозі
if [ -n "${PROJECT_SUBDIR}" ]; then
  SRC_DIR="${PROJECT_DIR}/${PROJECT_SUBDIR}"
else
  SRC_DIR="${PROJECT_DIR}"
fi

# збірка додатку
echo "building project"
cd "${SRC_DIR}"
sudo -u "${APP_USER}" chmod +x ./mvnw

# збираємо проект через maven від імені app_user
# використовую "bash -lc" щоб підвантажились змінні java_home та path
# "clean package" виконує повну збірку проєкту
# ключ "-Dmaven.test.skip=true" пропускає компіляцію та запуск тестів
# альтернативи запуску:
#   ./mvnw clean package                            — збірка з тестами
#   ./mvnw clean package -DskipTests                — пропустити тести, але скомпілювати
#   ./mvnw clean package -Dmaven.test.skip=true     — повністю пропустити тести
#   ./mvnw spring-boot:run                          — запуск застосунку без створення jar
sudo -u "${APP_USER}" bash -lc "./mvnw clean package -Dmaven.test.skip=true"

# шукаємо jar
JAR_PATH="$(ls -1 target/*.jar 2>/dev/null | head -n1)"
if [ -z "${JAR_PATH}" ]; then
  echo " ERROR: jar not found after build!"
  exit 1
else
  echo "build success, found JAR: ${JAR_PATH}"
fi

# копіюємо jar у app_dir
sudo -u "${APP_USER}" mkdir -p "${APP_DIR}"
sudo cp -f "${JAR_PATH}" "${APP_DIR}/app.jar"
sudo chown "${APP_USER}:${APP_USER}" "${APP_DIR}/app.jar"

# створюємо файл зі змінними для systemd-сервиса
sudo mkdir -p /etc/petclinic
cat <<ENV | sudo tee /etc/petclinic/petclinic.env >/dev/null
SPRING_PROFILES_ACTIVE=mysql
DB_HOST=${DB_HOST}
DB_PORT=${DB_PORT}
DB_NAME=${DB_NAME}
DB_USER=${DB_USER}
DB_PASS=${DB_PASS}
MYSQL_URL=jdbc:mysql://${DB_HOST}:${DB_PORT}/${DB_NAME}
MYSQL_USER=${DB_USER}
MYSQL_PASS=${DB_PASS}
JAVA_OPTS=
ENV

# створюємо сервіс (systemd)
echo "create service petclinic"
cat <<'SERVICE' | sudo tee /etc/systemd/system/petclinic.service >/dev/null
[Unit]
Description=Spring PetClinic
After=network.target

[Service]
EnvironmentFile=/etc/petclinic/petclinic.env
User=APPUSER_PLACEHOLDER
WorkingDirectory=APPDIR_PLACEHOLDER
ExecStart=/usr/bin/java $JAVA_OPTS -jar APPDIR_PLACEHOLDER/app.jar --spring.profiles.active=${SPRING_PROFILES_ACTIVE}
Restart=always
RestartSec=5

[Install]
WantedBy=multi-user.target
SERVICE

# підміняємо шаблоне значення
sudo sed -i "s|APPUSER_PLACEHOLDER|${APP_USER}|g" /etc/systemd/system/petclinic.service
sudo sed -i "s|APPDIR_PLACEHOLDER|${APP_DIR}|g" /etc/systemd/system/petclinic.service

# перезапускаємо сервіс
echo "enable & restart service petclinic"
sudo systemctl daemon-reload
sudo systemctl enable petclinic
sudo systemctl restart petclinic

echo "finish app.sh"
