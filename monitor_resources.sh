#!/bin/bash

# Загрузка переменных окружения
ENV_FILE="$HOME/.monitor_env"
[ -f "$ENV_FILE" ] && source "$ENV_FILE"

# PID-файлы
DISK_PID_FILE="/tmp/monitor_disk_pid"
MEM_PID_FILE="/tmp/monitor_mem_pid"

# Проверка, что переменные Telegram заданы
if [[ -z "$TELEGRAM_BOT_TOKEN" || -z "$TELEGRAM_CHAT_ID" ]]; then
  echo "❌ Не заданы TELEGRAM_BOT_TOKEN или TELEGRAM_CHAT_ID"
  exit 1
fi

# Имя хоста (ТОЛЬКО из .monitor_env)
HOST_NAME="${HOSTNAME:?HOSTNAME не задан. Проверь .monitor_env}"

# Функция отправки уведомлений
send_telegram_alert() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="<b>[$HOST_NAME]</b> $message" > /dev/null
}

# Проверка диска
check_disk_space() {
  while true; do
    disk_usage=$(df -h / | awk 'NR==2 {print $5}' | tr -d '%')

    if [ "$disk_usage" -ge 100 ]; then
      send_telegram_alert "❌ ДИСК ЗАПОЛНЕН НА 100%! Требуется немедленное вмешательство!"
    elif [ "$disk_usage" -ge 98 ]; then
      send_telegram_alert "🚨 Диск почти заполнен: ${disk_usage}%! Проверьте, освободите место."
    elif [ "$disk_usage" -ge 96 ]; then
      send_telegram_alert "⚠️ Предупреждение: диск заполнен на ${disk_usage}%."
    fi

    sleep 300
  done
}

# Проверка ОЗУ
check_memory() {
  while true; do
    mem_total=$(grep MemTotal /proc/meminfo | awk '{print $2}')
    mem_available=$(grep MemAvailable /proc/meminfo | awk '{print $2}')
    mem_used=$((mem_total - mem_available))
    mem_usage_percent=$((mem_used * 100 / mem_total))

    if [ "$mem_usage_percent" -ge 99 ]; then
      send_telegram_alert "❌ ОЗУ почти полностью занята (${mem_usage_percent}%)."
    elif [ "$mem_usage_percent" -ge 95 ]; then
      send_telegram_alert "🚨 Высокое потребление памяти: ${mem_usage_percent}%."
    elif [ "$mem_usage_percent" -ge 85 ]; then
      send_telegram_alert "⚠️ Использование памяти превышает 85% (${mem_usage_percent}%)."
    fi

    sleep 300
  done
}

# Запуск в фоне, если ещё не запущен
start_if_not_running() {
  local cmd="$1"
  local name="$2"
  local pid_file="$3"

  if [ -f "$pid_file" ] && kill -0 "$(cat "$pid_file")" 2>/dev/null; then
    echo "⚠️ $name уже запущен (PID $(cat "$pid_file"))"
  else
    nohup bash -c "$cmd" &> /dev/null &
    echo $! > "$pid_file"
    echo "✅ $name запущен (PID $!)"
  fi
}

# Запуск процессов
start_if_not_running "check_disk_space" "Проверка диска" "$DISK_PID_FILE"
start_if_not_running "check_memory" "Проверка памяти" "$MEM_PID_FILE"
