#!/bin/bash

# CatGPT Operations Script

# Load local config
SCRIPT_DIR="$(cd "$(dirname "${BASH_SOURCE[0]}")" && pwd)"
if [ -f "$SCRIPT_DIR/.env" ]; then
    source "$SCRIPT_DIR/.env"
else
    echo "Error: build/.env not found. Copy from .env.template"
    exit 1
fi

# Config
CONTAINER="${CONTAINER_NAME:-catgpt}"
OLLAMA_CONTAINER="${CONTAINER}-ollama"
COMPOSE_FILE="./build/docker-compose.yml"
MODEL="${OLLAMA_MODEL:-mistral}"

# Colors
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
RED='\033[0;31m'
CYAN='\033[0;36m'
NC='\033[0m'

# Helper functions
info() { echo -e "${CYAN}→ $1${NC}"; }
success() { echo -e "${GREEN}✓ $1${NC}"; }
warn() { echo -e "${YELLOW}! $1${NC}"; }
error() { echo -e "${RED}✗ $1${NC}"; }

confirm() {
    read -p "$1 [y/N] " -n 1 -r
    echo
    [[ $REPLY =~ ^[Yy]$ ]]
}

remote() {
    ssh $REMOTE "$1" || { error "SSH command failed"; return 1; }
}

show_menu() {
    echo ""
    echo -e "${GREEN}=== CatGPT Operations ===${NC}"
    echo ""
    echo -e "  ${CYAN}Deployment${NC}"
    echo "    1) Deploy (git push + restart)"
    echo "    2) Deploy via GitHub Actions"
    echo "    3) First-time setup (install Docker + clone)"
    echo ""
    echo -e "  ${CYAN}Monitoring${NC}"
    echo "    4) View logs (last 50)"
    echo "    5) Follow logs (live)"
    echo "    6) Check bot status"
    echo "    7) System status (full)"
    echo ""
    echo -e "  ${CYAN}Management${NC}"
    echo "    8) Restart bot"
    echo "    9) Shutdown (stop all)"
    echo "   10) Update bot token"
    echo ""
    echo -e "  ${CYAN}Ollama${NC}"
    echo "   11) Pull/update model"
    echo "   12) List models"
    echo "   13) Ollama logs"
    echo ""
    echo -e "  ${CYAN}Local${NC}"
    echo "   14) Run locally"
    echo "   15) Git status"
    echo "   16) Quick commit & push"
    echo ""
    echo -e "  ${CYAN}Other${NC}"
    echo "   17) SSH to server"
    echo "    0) Exit"
    echo ""
}

first_time_setup() {
    info "First-time setup for Oracle Cloud ARM instance"
    echo ""
    warn "Prerequisites:"
    echo "  1. SSH access configured (ssh $REMOTE should work)"
    echo "  2. Ubuntu 22.04 ARM instance"
    echo ""
    if ! confirm "Continue with setup?"; then return; fi

    info "Installing Docker..."
    remote "sudo apt-get update && sudo apt-get install -y ca-certificates curl gnupg"
    remote "sudo install -m 0755 -d /etc/apt/keyrings"
    remote "curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg"
    remote "sudo chmod a+r /etc/apt/keyrings/docker.gpg"
    remote "echo \"deb [arch=\$(dpkg --print-architecture) signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \$(. /etc/os-release && echo \"\$VERSION_CODENAME\") stable\" | sudo tee /etc/apt/sources.list.d/docker.list > /dev/null"
    remote "sudo apt-get update && sudo apt-get install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin"
    remote "sudo usermod -aG docker \$USER"
    success "Docker installed"

    info "Cloning repository..."
    local repo_url=$(git remote get-url origin)
    remote "git clone $repo_url $REMOTE_PATH || (cd $REMOTE_PATH && git pull)"
    success "Repository cloned"

    echo ""
    warn "Next steps:"
    echo "  1. Run: ./build/ops.sh token"
    echo "  2. Deploy: ./build/ops.sh deploy"
    echo "  3. Pull model: ./build/ops.sh model"
}

deploy_direct() {
    if ! confirm "Deploy directly via SSH?"; then return; fi
    local commit=$(git rev-parse HEAD)
    info "Deploying commit: $commit"

    # Push first
    git push origin main

    # SSH and deploy
    remote "cd $REMOTE_PATH && git fetch origin main && git reset --hard $commit"
    remote "export CONTAINER_NAME=$CONTAINER_NAME && sudo -E docker compose -f $REMOTE_PATH/build/docker-compose.yml up -d --force-recreate"

    success "Deployed!"
    sleep 5
    check_status
}

deploy_actions() {
    if ! confirm "Trigger GitHub Actions deploy?"; then return; fi
    local commit=$(git rev-parse HEAD)
    info "Deploying commit: $commit"

    git tag -d deploy 2>/dev/null
    git push origin :refs/tags/deploy 2>/dev/null
    git tag -a deploy -m "deploy" "$commit"
    git push origin refs/tags/deploy

    success "Deploy tag pushed. GitHub Actions will deploy automatically."
    echo "Monitor at: https://github.com/$(git remote get-url origin | sed 's/.*github.com[:/]//;s/.git$//')/actions"
}

view_logs() {
    info "Fetching bot logs..."
    remote "sudo docker logs $CONTAINER --tail 50"
}

follow_logs() {
    info "Following bot logs (Ctrl+C to stop)..."
    ssh $REMOTE "sudo docker logs $CONTAINER --tail 20 -f"
}

check_status() {
    info "Checking status..."
    echo ""
    echo -e "${GREEN}=== Bot ===${NC}"
    remote "sudo docker ps --filter name=^${CONTAINER}$ --format 'Container: {{.Names}}\nStatus: {{.Status}}'" || echo "  Not running"
    echo ""
    echo -e "${GREEN}=== Ollama ===${NC}"
    remote "sudo docker ps --filter name=^${OLLAMA_CONTAINER}$ --format 'Container: {{.Names}}\nStatus: {{.Status}}'" || echo "  Not running"
    echo ""
    echo -e "${GREEN}=== Resources ===${NC}"
    remote "sudo docker stats $CONTAINER $OLLAMA_CONTAINER --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}'" 2>/dev/null || echo "  Containers not running"
}

system_status() {
    info "Server Status"
    echo ""

    echo -e "${GREEN}=== System ===${NC}"
    remote "uptime"
    echo ""

    echo -e "${GREEN}=== Memory ===${NC}"
    remote "free -h | head -2"
    echo ""

    echo -e "${GREEN}=== CPU ===${NC}"
    remote "cat /proc/loadavg | awk '{print \"Load: \"\$1\" \"\$2\" \"\$3}'"
    remote "nproc | xargs -I{} echo 'Cores: {}'"
    echo ""

    echo -e "${GREEN}=== Disk ===${NC}"
    remote "df -h / | tail -1 | awk '{print \"Used: \"\$3\" / \"\$2\" (\"\$5\")\"}'"
    echo ""

    echo -e "${GREEN}=== Docker ===${NC}"
    remote "sudo docker ps -a --format 'table {{.Names}}\t{{.Status}}\t{{.Ports}}'"
    echo ""

    echo -e "${GREEN}=== Resource Usage ===${NC}"
    remote "sudo docker stats --no-stream --format 'table {{.Name}}\t{{.CPUPerc}}\t{{.MemUsage}}\t{{.NetIO}}'"
}

restart_bot() {
    if ! confirm "Restart bot?"; then return; fi
    info "Restarting..."
    remote "sudo docker restart $CONTAINER"
    success "Restarted. Waiting..."
    sleep 3
    remote "sudo docker logs $CONTAINER --tail 10"
}

shutdown_bot() {
    if ! confirm "Stop all containers?"; then return; fi
    info "Stopping containers..."
    remote "cd $REMOTE_PATH && sudo docker compose -f $COMPOSE_FILE down"
    success "Stopped!"
}

update_token() {
    warn "This will update the bot token on the server"
    echo -e "${YELLOW}Enter new BOT_TOKEN (hidden):${NC}"
    read -rs token
    echo
    if [ -z "$token" ]; then
        error "No token provided. Cancelled."
        return
    fi
    if ! confirm "Update token and restart?"; then return; fi

    info "Updating token..."
    ssh $REMOTE "cat > $REMOTE_PATH/build/.env << ENVEOF
# App config
BOT_TOKEN='$token'
OLLAMA_MODEL='$MODEL'
NODE_ENV='production'

# Deployment config
REMOTE_PATH='$REMOTE_PATH'
CONTAINER_NAME='$CONTAINER_NAME'
ENVEOF"

    info "Recreating container..."
    remote "cd $REMOTE_PATH && sudo docker compose -f $COMPOSE_FILE up -d --force-recreate"
    sleep 5
    remote "sudo docker logs $CONTAINER --tail 10"
    success "Token updated!"
}

pull_model() {
    info "Pulling model: $MODEL"
    remote "sudo docker exec $OLLAMA_CONTAINER ollama pull $MODEL"
    success "Model pulled!"
}

list_models() {
    info "Listing models on server..."
    remote "sudo docker exec $OLLAMA_CONTAINER ollama list"
}

ollama_logs() {
    info "Fetching Ollama logs..."
    remote "sudo docker logs $OLLAMA_CONTAINER --tail 50"
}

run_local() {
    info "Running locally (Ctrl+C to stop)..."
    echo "Make sure Ollama is running: ollama serve"
    echo "Set OLLAMA_HOST=http://localhost:11434 in build/.env"
    echo ""
    npm start
}

git_status() {
    info "Git status:"
    git status --short
    echo ""
    info "Recent commits:"
    git log --oneline -5
    echo ""
    info "Unpushed commits:"
    git log --oneline @{u}..HEAD 2>/dev/null || echo "  (none or no upstream)"
}

quick_commit() {
    git_status
    echo ""
    if ! confirm "Stage all and commit?"; then return; fi
    echo -e "${YELLOW}Enter commit message:${NC}"
    read -r msg
    if [ -z "$msg" ]; then
        error "No message provided. Cancelled."
        return
    fi
    git add -A
    git commit -m "$msg"
    if confirm "Push now?"; then
        git push
        success "Pushed!"
    fi
}

ssh_server() {
    info "Connecting to server..."
    ssh $REMOTE
}

# Single command mode
if [ -n "$1" ]; then
    case $1 in
        setup) first_time_setup ;;
        deploy) deploy_direct ;;
        actions) deploy_actions ;;
        logs) view_logs ;;
        follow) follow_logs ;;
        status) check_status ;;
        system) system_status ;;
        restart) restart_bot ;;
        shutdown) shutdown_bot ;;
        token) update_token ;;
        model) pull_model ;;
        models) list_models ;;
        ollama-logs) ollama_logs ;;
        local) run_local ;;
        git) git_status ;;
        commit) quick_commit ;;
        ssh) ssh_server ;;
        *) echo "Usage: $0 [setup|deploy|actions|logs|follow|status|system|restart|shutdown|token|model|models|ollama-logs|local|git|commit|ssh]"; exit 1 ;;
    esac
    exit 0
fi

# Interactive mode
while true; do
    show_menu
    read -p "Select option: " choice
    case $choice in
        1) deploy_direct ;;
        2) deploy_actions ;;
        3) first_time_setup ;;
        4) view_logs ;;
        5) follow_logs ;;
        6) check_status ;;
        7) system_status ;;
        8) restart_bot ;;
        9) shutdown_bot ;;
        10) update_token ;;
        11) pull_model ;;
        12) list_models ;;
        13) ollama_logs ;;
        14) run_local ;;
        15) git_status ;;
        16) quick_commit ;;
        17) ssh_server ;;
        0) echo "Bye!"; exit 0 ;;
        *) error "Invalid option" ;;
    esac
done
