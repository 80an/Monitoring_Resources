#!/bin/bash

# Цвета
B_GREEN="\e[32m"
B_YELLOW="\e[33m"
B_RED="\e[31m"
NO_COLOR="\e[0m"

MONITOR_PID_FILE="/tmp/monitor_pid"
ENV_FILE="$HOME/.monitor_env"

# Загрузка .env, если существует
if [ -f "$ENV_FILE" ]; then
  source "$ENV_FILE"
fi

# Проверка и запрос недостающих переменных
if [ -z "$HOSTNAME" ]; then
  read -p "Введите имя сервера (HOSTNAME): " HOSTNAME
  echo "HOSTNAME=$HOSTNAME" >> "$ENV_FILE"
  export HOSTNAME
fi

if [ -z "$TELEGRAM_BOT_TOKEN" ] || [ -z "$TELEGRAM_CHAT_ID" ]; then
  echo -e "${B_YELLOW}🔧 Настройка Telegram...${NO_COLOR}"
  read -p "Введите Telegram Bot Token: " TELEGRAM_BOT_TOKEN
  read -p "Введите Telegram Chat ID: " TELEGRAM_CHAT_ID
  echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" >> "$ENV_FILE"
  echo "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID" >> "$ENV_FILE"
  export TELEGRAM_BOT_TOKEN
  export TELEGRAM_CHAT_ID
  echo -e "${B_GREEN}✅ Telegram настройки сохранены.${NO_COLOR}"
fi

# Настройка Telegram
setup_telegram() {
  echo -e "${B_YELLOW}🔧 Настройка Telegram...${NO_COLOR}"
  read -p "Введите Telegram Bot Token: " TELEGRAM_BOT_TOKEN
  read -p "Введите Telegram Chat ID: " TELEGRAM_CHAT_ID
  echo "TELEGRAM_BOT_TOKEN=$TELEGRAM_BOT_TOKEN" > "$ENV_FILE"
  echo "TELEGRAM_CHAT_ID=$TELEGRAM_CHAT_ID" >> "$ENV_FILE"
  echo -e "${B_GREEN}✅ Telegram настройки сохранены.${NO_COLOR}"
}

# Настройка имени сервера
setup_hostname() {
  read -p "Введите новое имя сервера (HOSTNAME): " HOSTNAME
  if grep -q "^HOSTNAME=" "$ENV_FILE" 2>/dev/null; then
    sed -i "s/^HOSTNAME=.*/HOSTNAME=$HOSTNAME/" "$ENV_FILE"
  else
    echo "HOSTNAME=$HOSTNAME" >> "$ENV_FILE"
  fi
  export HOSTNAME
  echo -e "${B_GREEN}✅ Имя сервера обновлено: $HOSTNAME${NO_COLOR}"
}

# Отправка сообщений в Telegram
send_telegram_alert() {
  local message="$1"
  curl -s -X POST "https://api.telegram.org/bot$TELEGRAM_BOT_TOKEN/sendMessage" \
    -d chat_id="$TELEGRAM_CHAT_ID" \
    -d parse_mode="HTML" \
    -d text="$message" > /dev/null
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
  nohup bash -c "source <(wget -qO- 'https://raw.githubusercontent.com/80an/Monitoring_Resources/refs/heads/main/monitor_resources.sh')" &> /dev/null &
  MONITOR_PID=$!
  echo "$MONITOR_PID" > "$MONITOR_PID_FILE"
  echo -e "${B_GREEN}✅ Мониторинг запущен с PID $MONITOR_PID${NO_COLOR}"

  local disk_usage=$(df -h / | awk 'NR==2{print $5}')
  local mem_info=$(free -h | awk '/Mem:/{print $3 " / " $2}')

  read -r -d '' message <<EOF
<b>✅ Мониторинг ресурсов запущен</b>

🖥️ <b>Сервер:</b> <code>$HOSTNAME</code>
🆔 <code>$MONITOR_PID</code>

📊 <b>Ресурсы:</b>
• 💾 Диск: $disk_usage
• 🧠 RAM: $mem_info
EOF

  send_telegram_alert "$message"
}

# Остановка фоновых процессов
stop_background_monitors() {
  local stopped_any=false
  for pid_file in /tmp/monitor_disk_pid /tmp/monitor_mem_pid; do
    if [ -f "$pid_file" ]; then
      PID=$(cat "$pid_file")
      if kill -0 "$PID" 2>/dev/null; then
        kill "$PID"
        echo -e "${B_RED}⛔ Процесс (PID $PID) остановлен [$(basename "$pid_file")]${NO_COLOR}"
        send_telegram_alert "⛔ <b>Фоновый процесс остановлен</b>\n🖥️ <code>$HOSTNAME</code>\n📄 <code>$(basename "$pid_file")</code> (PID $PID)"
        stopped_any=true
      fi
      rm -f "$pid_file"
    fi
  done

  if ! $stopped_any; then
    echo -e "${B_YELLOW}⚠️ Фоновые процессы не найдены${NO_COLOR}"
  fi
}

# Остановка мониторинга
stop_monitoring() {
  if [ -f "$MONITOR_PID_FILE" ]; then
    MONITOR_PID=$(cat "$MONITOR_PID_FILE")
    if kill -0 "$MONITOR_PID" 2>/dev/null; then
      kill "$MONITOR_PID"
      echo -e "${B_RED}⛔ Мониторинг остановлен (PID $MONITOR_PID)${NO_COLOR}"
      rm -f "$MONITOR_PID_FILE"
      send_telegram_alert "⛔ <b>Мониторинг остановлен</b>\n🖥️ <code>$HOSTNAME</code>\n🆔 <code>$MONITOR_PID</code>"
    else
      echo -e "${B_YELLOW}⚠️ Процесс мониторинга не найден. Удаляю PID-файл.${NO_COLOR}"
      rm -f "$MONITOR_PID_FILE"
    fi
  else
    echo -e "${B_RED}🚫 Мониторинг не запущен${NO_COLOR}"
  fi
  stop_background_monitors
}

# Проверка статуса
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
  echo -e "5) 🖋 Сменить имя сервера"
  echo -e "6) ❌ Выход"
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
    5) setup_hostname ;;
    6)
      echo -e "${B_YELLOW}👋 Выход...${NO_COLOR}"
      break
      ;;
    *) echo -e "${B_RED}Неверный выбор. Повторите.${NO_COLOR}" ;;
  esac
done
