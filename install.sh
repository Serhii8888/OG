#!/bin/bash

GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"

set -e

echo -e "${GREEN}Telegram канал для підтримки: @nodesua${NC}"

echo -e "${GREEN}Меню керування 0g:${NC}"
echo "1. Встановити або оновити ноду"
echo "2. Перевірити статус ноди"
echo "3. Перевірити піри"
echo "4. Переглянути логи"
echo "5. Перезапустити ноду"
echo "6. Видалити ноду"
echo -n "Введіть номер дії: "
read CHOICE

NODE_DIR="$HOME/0g-storage-node"
CONFIG_URL="https://raw.githubusercontent.com/0glabs/0g-storage-node/main/run/config.toml"

install_or_update_node() {
    echo -e "${GREEN}Оновлення системи та встановлення залежностей...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt-get install -y curl iptables build-essential git wget lz4 jq make cmake gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip libleveldb-dev screen ufw

    echo -e "${GREEN}Встановлення або оновлення Rust...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    rustc --version

    echo -e "${GREEN}Встановлення або оновлення Go...${NC}"
    GO_VERSION="1.24.3"
    wget -q https://go.dev/dl/go${GO_VERSION}.linux-amd64.tar.gz
    sudo rm -rf /usr/local/go
    sudo tar -C /usr/local -xzf go${GO_VERSION}.linux-amd64.tar.gz
    rm go${GO_VERSION}.linux-amd64.tar.gz

    if ! grep -q "/usr/local/go/bin" <<< "$PATH"; then
      echo 'export PATH=$PATH:/usr/local/go/bin' >> ~/.bashrc
      export PATH=$PATH:/usr/local/go/bin
    fi

    go version

    if [ ! -d "$NODE_DIR" ]; then
        echo -e "${GREEN}Клонуємо репозиторій 0g-storage-node...${NC}"
        git clone https://github.com/0glabs/0g-storage-node.git $NODE_DIR
    else
        echo -e "${GREEN}Оновлюємо репозиторій 0g-storage-node...${NC}"
        cd $NODE_DIR
        git fetch --all
        git reset --hard origin/main
    fi

    cd $NODE_DIR

    echo -e "${GREEN}Оновлюємо підмодулі...${NC}"
    git submodule update --init --recursive

    echo -e "${GREEN}Збираємо проект... це може зайняти декілька хвилин${NC}"
    cargo build --release

    mkdir -p $NODE_DIR/run

    echo -e "${GREEN}Завантажуємо конфігурацію з офіційного репозиторію...${NC}"
    curl -sSfL $CONFIG_URL -o $NODE_DIR/run/config.toml

    echo -n "Вставте приватний ключ вашого гаманця (без 0x): "
    read PRIVATE_KEY

    if [[ ! $PRIVATE_KEY =~ ^[a-fA-F0-9]{64}$ ]]; then
        echo -e "${RED}Неправильний формат приватного ключа!${NC}"
        exit 1
    fi

    echo -e "${GREEN}Вставляємо приватний ключ у конфігурацію...${NC}"
    sed -i "s|^miner_key = \".*\"|miner_key = \"$PRIVATE_KEY\"|" $NODE_DIR/run/config.toml

    echo -e "${GREEN}Створюємо systemd сервіс...${NC}"
    sudo tee /etc/systemd/system/zgs.service > /dev/null <<EOF
[Unit]
Description=0G Storage Node
After=network.target

[Service]
User=$USER
WorkingDirectory=$NODE_DIR/run
ExecStart=$NODE_DIR/target/release/zgs_node --config $NODE_DIR/run/config.toml
Restart=on-failure
RestartSec=10
LimitNOFILE=65535

[Install]
WantedBy=multi-user.target
EOF

    echo -e "${GREEN}Перезавантажуємо systemd, запускаємо і вмикаємо сервіс автозапуску...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable zgs
    sudo systemctl restart zgs

    echo -e "${GREEN}✅ Встановлення або оновлення завершено.${NC}"
}

check_status() {
    sudo systemctl status zgs --no-pager
}

check_peers() {
    echo -e "${GREEN}Перевірка пірів (натисніть Ctrl+C для виходу)...${NC}"
    while true; do
        response=$(curl -s -X POST http://localhost:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
        logSyncHeight=$(echo $response | jq '.result.logSyncHeight')
        connectedPeers=$(echo $response | jq '.result.connectedPeers')
        echo -e "logSyncHeight: \033[32m$logSyncHeight\033[0m, connectedPeers: \033[34m$connectedPeers\033[0m"
        sleep 5
    done
}

show_logs() {
    LOG_FILE="$NODE_DIR/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo -e "${RED}Лог-файл не знайдено: $LOG_FILE${NC}"
    fi
}

restart_node() {
    sudo systemctl restart zgs
    echo -e "${GREEN}Нода перезапущена.${NC}"
}

remove_node() {
    sudo systemctl stop zgs || true
    sudo systemctl disable zgs || true
    sudo rm -f /etc/systemd/system/zgs.service
    sudo systemctl daemon-reload
    rm -rf $NODE_DIR
    echo -e "${GREEN}✅ Вузол успішно видалено.${NC}"
}

case $CHOICE in
  1)
    install_or_update_node
    ;;
  2)
    check_status
    ;;
  3)
    check_peers
    ;;
  4)
    show_logs
    ;;
  5)
    restart_node
    ;;
  6)
    remove_node
    ;;
  *)
    echo -e "${RED}Невірний вибір.${NC}"
    ;;
esac
