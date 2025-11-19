#!/bin/bash
echo "🚀 Настройка Alertmanager с Telegram уведомлениями"
echo "=================================================="

# Запрос данных у пользователя
echo -n "Введите TELEGRAM_CHAT_ID: "
read -s TELEGRAM_CHAT_ID
echo
echo -n "Введите TELEGRAM_BOT_TOKEN: " 
read -s TELEGRAM_BOT_TOKEN
echo

# Проверка введенных данных
if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
    echo "❌ Ошибка: Все поля должны быть заполнены!"
    exit 1
fi

# Создаем .env файл
cat > .env << EOF
TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN
TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID
EOF

echo "✅ Файл .env создан"

# Генерируем alertmanager.yml
cat > alertmanager.yml << EOF
global:
  resolve_timeout: 5m

route:
  receiver: "homelabmonitor"

receivers:
  - name: "homelabmonitor"
    telegram_configs:
      - bot_token: "$TELEGRAM_BOT_TOKEN"
        chat_id: $TELEGRAM_CHAT_ID
        parse_mode: "HTML"
        message: '{{ template "telegram.default.message" . }}'
EOF

echo "✅ Конфиг alertmanager.yml создан"

# Запускаем Docker Compose
echo "🚀 Запускаем Alertmanager..."
docker compose up --build -d

# Проверяем статус
if [ $? -eq 0 ]; then
    echo "✅ Alertmanager успешно запущен!"
    echo "📊 Проверить статус: docker compose ps"
    echo "📋 Посмотреть логи: docker compose logs alertmanager"
    echo "🌐 Веб-интерфейс: http://localhost:9093"
else
    echo "❌ Ошибка при запуске Alertmanager"
    exit 1
fi
