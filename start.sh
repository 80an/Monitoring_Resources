#!/bin/bash

ENV_FILE=".monitor_env"

# Загрузка переменных
load_env() {
  if [[ -f "$ENV_FILE" ]]; then
    source "$ENV_FILE"
  fi
}

# Сохранение переменных
save_env() {
  cat > "$ENV_FILE" <<EOF
SERVER_NAME="$SERVER_NAME"
TELEGRAM_TOKEN="$TELEGRAM_TOKEN"
TELEGRAM_CHAT_ID="$TELEGRAM_CHAT_ID"
EOF
}

# Запрос переменных
ask_env_variables() {
  echo "Введите имя сервера:"
  read -r SERVER_NAME
  echo "Введите Telegram токен:"
  read -r TELEGRAM_TOKEN
  echo "Введите Telegram чат ID:"
  read -r TELEGRAM_CHAT_ID
  save_env
}

# Проверка переменных
check_env() {
  load_env
  if [[ -z "$SERVER_NAME" || -z "$TELEGRAM_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
    ask_env_variables
  fi
}

# Отправка сообщений в Telegram
send_telegram() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="$message" > /dev/null
}

# Мониторинг диска
start_disk_monitoring() {
  cat > /tmp/check_disk_space.sh <<'EOF'
#!/bin/bash
while true; do
  USAGE=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')
  if (( USAGE > 90 )); then
    source .monitor_env
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" \
      -d parse_mode="HTML" \
      -d text="<b>[$SERVER_NAME]</b> 💾 Диск заполнен на ${USAGE}%!"
  fi
  sleep 300
done
EOF
  chmod +x /tmp/check_disk_space.sh
  nohup bash /tmp/check_disk_space.sh > /dev/null 2>&1 &
  echo $! > /tmp/check_disk_space.pid
  echo "Мониторинг диска запущен"
}

# Мониторинг RAM
start_memory_monitoring() {
  cat > /tmp/check_memory.sh <<'EOF'
#!/bin/bash
while true; do
  USED=$(free | awk '/Mem:/ {printf("%.0f", $3/$2 * 100)}')
  if (( USED > 90 )); then
    source .monitor_env
    curl -s -X POST "https://api.telegram.org/bot${TELEGRAM_TOKEN}/sendMessage" \
      -d chat_id="$TELEGRAM_CHAT_ID" \
      -d parse_mode="HTML" \
      -d text="<b>[$SERVER_NAME]</b> 🧠 Память используется на ${USED}%!"
  fi
  sleep 300
done
EOF
  chmod +x /tmp/check_memory.sh
  nohup bash /tmp/check_memory.sh > /dev/null 2>&1 &
  echo $! > /tmp/check_memory.pid
  echo "Мониторинг памяти запущен"
}

# Проверка запущенных процессов
check_monitoring_status() {
  echo "Статус мониторинга:"
  if [[ -f /tmp/check_disk_space.pid && -d /proc/$(cat /tmp/check_disk_space.pid) ]]; then
    echo "💾 Диск: Запущен"
  else
    echo "💾 Диск: Не запущен"
  fi
  if [[ -f /tmp/check_memory.pid && -d /proc/$(cat /tmp/check_memory.pid) ]]; then
    echo "🧠 Память: Запущен"
  else
    echo "🧠 Память: Не запущен"
  fi
}

# Остановка мониторинга
stop_all_monitoring() {
  for pidfile in /tmp/check_disk_space.pid /tmp/check_memory.pid; do
    if [[ -f $pidfile ]]; then
      kill "$(cat $pidfile)" 2>/dev/null
      rm -f "$pidfile"
    fi
  done
  echo "Все мониторинги остановлены"
}

# Настройка переменных
edit_variables() {
  echo "Текущие значения:"
  echo "Имя сервера: $SERVER_NAME"
  echo "Telegram токен: $TELEGRAM_TOKEN"
  echo "Telegram чат ID: $TELEGRAM_CHAT_ID"
  echo ""
  ask_env_variables
}

# Главное меню
main_menu() {
  while true; do
    echo ""
    echo "📊 Меню мониторинга [$SERVER_NAME]"
    echo "1. Запустить мониторинг дискового пространства"
    echo "2. Запустить мониторинг RAM"
    echo "3. Проверить статус мониторинга"
    echo "4. Остановить все запущенные мониторинги"
    echo "5. Настроить переменные"
    echo "6. Выход"
    echo -n "Выберите пункт: "
    read -r choice

    case $choice in
      1) start_disk_monitoring ;;
      2) start_memory_monitoring ;;
      3) check_monitoring_status ;;
      4) stop_all_monitoring ;;
      5) edit_variables ;;
      6) break ;;
      *) echo "Неверный выбор" ;;
    esac
  done
}

# Запуск
check_env
main_menu
