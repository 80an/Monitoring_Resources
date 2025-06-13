#!/bin/bash

# Цвета
B_GREEN="\e[32m"
B_YELLOW="\e[33m"
B_RED="\e[31m"
NO_COLOR="\e[0m"

MONITOR_PID_FILE="/tmp/monitor_pid"
ENV_FILE="$HOME/.monitor_env"
MONITOR_SCRIPT="/tmp/monitor_resources.sh"

# Загрузка .env, если существует
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# Настройка Telegram и имени сервера
setup_telegram() {
  echo -e "${B_YELLOW}🔧 Настройка Telegram...${NO_COLOR}"
  read -p "Введите Telegram Bot Token: " TELEGRAM_BOT_TOKEN
  read -p "Введите Telegram Chat ID: " TELEGRAM_CHAT_ID
  read -p "Введите имя сервера (ServerName): " SERVER_NAME
  echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" > "$ENV_FILE"
  echo "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID" >> "$ENV_FILE"
  echo "SERVER_NAME=$SERVER_NAME" >> "$ENV_FILE"
  echo -e "${B_GREEN}✅ Telegram настройки сохранены.${NO_COLOR}"
}

# Отправка сообщений в Telegram
send_telegram_alert() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="<b>[$SERVER_NAME]</b> $message" > /dev/null
}

# Получение информации о системе
get_system_info() {
  local disk_usage=$(df -h / | awk 'NR==2{print $5}')
  local mem_info=$(free -h | awk '/Mem:/{print $3 " / " $2}')
  echo -e "📊 <b>Ресурсы:</b>\n• 💾 Диск: $disk_usage\n• 🧠 RAM: $mem_info"
}

# Запуск мониторинга
start_monitoring() {
  if [ -f "$MONITOR_PID_FILE" ] && kill -0 "$(cat "$MONITOR_PID_FILE")" 2>/dev/null; then
    echo -e "${B_YELLOW}⚠️ Мониторинг уже запущен (PID $(cat $MONITOR_PID_FILE))${NO_COLOR}"
    return
  fi

  echo -e "${B_GREEN}▶️ Запуск мониторинга...${NO_COLOR}"
  wget -qO "$MONITOR_SCRIPT" "https://raw.githubusercontent.com/80an/Nodes/main/!tools/monitor_resources.sh"
  chmod +x "$MONITOR_SCRIPT"

  nohup bash "$MONITOR_SCRIPT" "$ENV_FILE" &> /dev/null &
  MONITOR_PID=$!
  echo "$MONITOR_PID" > "$MONITOR_PID_FILE"
  echo -e "${B_GREEN}✅ Мониторинг запущен с PID $MONITOR_PID${NO_COLOR}"

  local info="$(get_system_info)"
  send_telegram_alert "✅ <b>Мониторинг ресурсов запущен</b>\n\n🆔 <code>$MONITOR_PID</code>\n\n$info"
}

# Остановка мониторинга
stop_monitoring() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    MONITOR_PID=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
      kill "$MONITOR_PID"
      echo -e "${B_RED}⛔ Мониторинг остановлен (PID $MONITOR_PID)${NO_COLOR}"
      send_telegram_alert "⛔ Мониторинг остановлен (PID $MONITOR_PID)"
    else
      echo -e "${B_YELLOW}⚠️ Процесс мониторинга не найден. Удаляю PID-файл.${NO_COLOR}"
    fi
    rm -f "$MONITOR_PID_FILE"
  else
    echo -e "${B_RED}🚫 Мониторинг не запущен${NO_COLOR}"
  fi
}

# Проверка статуса мониторинга
check_status() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    MONITOR_PID=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
      echo -e "${B_GREEN}✅ Мониторинг работает (PID $MONITOR_PID)${NO_COLOR}"
    else
      echo -e "${B_YELLOW}⚠️ Мониторинг неактивен, но PID-файл существует${NO_COLOR}"
    fi
  else
    echo -e "${B_RED}❌ Мониторинг не запущен${NO_COLOR}"
  fi
}

# Меню
menu() {
  echo
  echo -e "${B_YELLOW}========= 🛠 Меню управления мониторингом ресурсов =========${NO_COLOR}"
  echo -e "1) ▶️  Запустить мониторинг"
  echo -e "2) ⏹  Остановить мониторинг"
  echo -e "3) ℹ️  Проверить статус мониторинга"
  echo -e "4) ⚙️  Настроить Telegram"
  echo -e "5) ❌ Выход"
  echo -e "${B_YELLOW}======================================================${NO_COLOR}"
}

# Основной цикл
while true; do
  menu
  read -p "Выберите действие: " choice
  case $choice in
    1) start_monitoring ;;
    2) stop_monitoring ;;
    3) check_status ;;
    4) setup_telegram ;;
    5)
      echo -e "${B_YELLOW}👋 Выход...${NO_COLOR}"
      break
      ;;
    *) echo -e "${B_RED}Неверный выбор. Повторите.${NO_COLOR}" ;;
  esac
done
