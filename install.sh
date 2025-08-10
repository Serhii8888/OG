#!/bin/bash

GREEN="\e[32m"
RED="\e[31m"
NC="\e[0m"

echo -e "${GREEN}Telegram канал для підтримки: @nodesua${NC}"

echo -e "${GREEN}Меню керування 0g:${NC}"
echo "1. Встановити ноду"
echo "2. Перевірити статус ноди"
echo "3. Перевірити піри"
echo "4. Перевірити логи"
echo "5. Перезапустити ноду"
echo "6. Видалити ноду"
echo -n "Введіть номер дії: "
read CHOICE

case $CHOICE in
  1)
    echo -e "${GREEN}Оновлення системи та встановлення залежностей...${NC}"
    sudo apt-get update && sudo apt-get upgrade -y
    sudo apt install -y curl iptables build-essential git wget lz4 jq make cmake gcc nano automake autoconf tmux htop nvme-cli libgbm1 pkg-config libssl-dev libleveldb-dev tar clang bsdmainutils ncdu unzip screen ufw

    echo -e "${GREEN}Встановлення або оновлення Rust...${NC}"
    curl --proto '=https' --tlsv1.2 -sSf https://sh.rustup.rs | sh -s -- -y
    source $HOME/.cargo/env
    rustc --version

    echo -e "${GREEN}Встановлення Go 1.24.3...${NC}"
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

    echo -e "${GREEN}Клонування або оновлення репозиторію 0g-storage-node...${NC}"
    NODE_DIR="$HOME/0g-storage-node"
    if [ ! -d "$NODE_DIR" ]; then
      git clone https://github.com/0glabs/0g-storage-node.git "$NODE_DIR"
    else
      cd "$NODE_DIR"
      git fetch --all
      git reset --hard origin/main
    fi
    cd "$NODE_DIR"
    git submodule update --init --recursive

    echo -e "${GREEN}Збірка проекту (release)...${NC}"
    cargo build --release

    mkdir -p "$NODE_DIR/run"

    echo -e "${GREEN}Завантаження свіжого конфігу...${NC}"
    curl -sSfL https://raw.githubusercontent.com/0glabs/0g-storage-node/main/run/config.toml -o "$NODE_DIR/run/config.toml"

    read -p "Вставте приватний ключ вашого гаманця (0x...): " PRIVATE_KEY
    if [[ ! $PRIVATE_KEY =~ ^0x[a-fA-F0-9]{64}$ ]]; then
        echo -e "${RED}Неправильний формат приватного ключа!${NC}"
        exit 1
    fi
    # В config має бути без 0x префікса
    PRIVATE_KEY_NO_PREFIX=${PRIVATE_KEY:2}
    sed -i "s|^miner_key = \".*\"|miner_key = \"$PRIVATE_KEY_NO_PREFIX\"|" "$NODE_DIR/run/config.toml"

    echo -e "${GREEN}Створення systemd сервісу...${NC}"
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

    echo -e "${GREEN}Перезавантаження systemd, запуск та увімкнення сервісу...${NC}"
    sudo systemctl daemon-reload
    sudo systemctl enable zgs
    sudo systemctl restart zgs

    echo -e "${GREEN}✅ Встановлення завершено.${NC}"
    ;;

  2)
    echo -e "${GREEN}Перевірка статусу ноди...${NC}"
    sudo systemctl status zgs --no-pager
    ;;

  3)
    echo -e "${GREEN}Перевірка пірів (Ctrl+C для виходу)...${NC}"
    while true; do
        response=$(curl -s -X POST http://localhost:5678 -H "Content-Type: application/json" -d '{"jsonrpc":"2.0","method":"zgs_getStatus","params":[],"id":1}')
        logSyncHeight=$(echo $response | jq '.result.logSyncHeight')
        connectedPeers=$(echo $response | jq '.result.connectedPeers')
        echo -e "logSyncHeight: \033[32m$logSyncHeight\033[0m, connectedPeers: \033[34m$connectedPeers\033[0m"
        sleep 5
    done
    ;;

  4)
    echo -e "${GREEN}Перегляд логів...${NC}"
    LOG_FILE="$HOME/0g-storage-node/run/log/zgs.log.$(TZ=UTC date +%Y-%m-%d)"
    if [ -f "$LOG_FILE" ]; then
        tail -f "$LOG_FILE"
    else
        echo -e "${RED}Лог-файл не знайдено: $LOG_FILE${NC}"
    fi
    ;;

  5)
    echo -e "${GREEN}Перезапуск ноди...${NC}"
    sudo systemctl restart zgs
    ;;

  6)
    echo -e "${RED}Видалення ноди...${NC}"
    sudo systemctl stop zgs || true
    sudo systemctl disable zgs || true
    sudo rm -f /etc/systemd/system/zgs.service
    sudo systemctl daemon-reload
    rm -rf "$HOME/0g-storage-node"
    echo -e "${GREEN}✅ Вузол успішно видалено.${NC}"
    ;;

  *)
    echo -e "${RED}Невірний вибір.${NC}"
    ;;
esac
