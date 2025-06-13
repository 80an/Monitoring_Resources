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

# Функция проверки дискового пространства
check_disk_space() {
  while true; do
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    if [ "$disk_usage" -ge 100 ]; then
      send_telegram "❌ <b>ДИСК ЗАПОЛНЕН НА 100%</b>! Требуется немедленное вмешательство!"
    elif [ "$disk_usage" -ge 98 ]; then
      send_telegram "🚨 <b>Диск почти заполнен:</b> ${disk_usage}%! Проверьте, освободите место."
    elif [ "$disk_usage" -ge 96 ]; then
      send_telegram "⚠️ <b>Предупреждение:</b> диск заполнен на ${disk_usage}%. Задумайтесь о том, чтобы освободить место."
    fi

    sleep 300  # Проверка каждые 5 минут
  done
}

# Функция проверки оперативной памяти
check_memory() {
  while true; do
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))
    mem_usage_percent=$((mem_used * 100 / mem_total))

    if [ "$mem_usage_percent" -ge 99 ]; then
      send_telegram "❌ <b>ОЗУ почти полностью занята</b> (${mem_usage_percent}%). Требуется немедленная проверка!"
    elif [ "$mem_usage_percent" -ge 95 ]; then
      send_telegram "🚨 <b>Высокое потребление памяти:</b> ${mem_usage_percent}%. Рассмотрите возможность оптимизации."
    elif [ "$mem_usage_percent" -ge 85 ]; then
      send_telegram "⚠️ <b>Использование памяти превышает 85%</b> (${mem_usage_percent}%)."
    fi

    sleep 300  # Проверка каждые 5 минут
  done
}

# Запуск мониторинга диска
start_disk_monitoring() {
  if [[ -f /tmp/check_disk_space.pid && -d /proc/$(cat /tmp/check_disk_space.pid) ]]; then
    echo "Мониторинг диска уже запущен."
  else
    check_disk_space &  # Запуск в фоне
    MONITOR_PID=$!
    echo "$MONITOR_PID" > /tmp/check_disk_space.pid

    disk_usage=$(df -h / | awk 'NR==2 {print $5}')

    send_telegram "<b>✅ Мониторинг ресурсов запущен</b>

🖥️ <b>Сервер:</b> <code>$SERVER_NAME</code>
🆔 <code>$MONITOR_PID</code>

📊 <b>Ресурсы:</b>
• 💾 Диск: $disk_usage"

    echo "Мониторинг диска запущен."
  fi
}


# Запуск мониторинга памяти
start_memory_monitoring() {
  if [[ -f /tmp/check_memory.pid && -d /proc/$(cat /tmp/check_memory.pid) ]]; then
    echo "Мониторинг памяти уже запущен."
  else
    check_memory &  # Запуск в фоне
    MONITOR_PID=$!
    echo "$MONITOR_PID" > /tmp/check_memory.pid

    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))
    mem_usage_percent=$((mem_used * 100 / mem_total))

    send_telegram "<b>✅ Мониторинг ресурсов запущен</b>

🖥️ <b>Сервер:</b> <code>$SERVER_NAME</code>
🆔 <code>$MONITOR_PID</code>

📊 <b>Ресурсы:</b>
• 🧠 Память: ${mem_usage_percent}%"

    echo "Мониторинг памяти запущен."
  fi
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
