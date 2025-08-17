#!/bin/bash

# =============================================================================
# Script d'installation complète pour Ubuntu Server 24.04.3 LTS
# Inclut configuration système, outils de développement et Freqtrade
# Version corrigée avec sécurité renforcée et utilisateur dédié
# =============================================================================

set -euo pipefail  # Arrêter en cas d'erreur

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables globales
PYTHON_VERSION="3.11.9"  # Version stable pour compatibilité TF/PyTorch
FREQTRADE_USER="freqtrade"
FREQTRADE_HOME="/home/$FREQTRADE_USER"
FREQTRADE_DIR="$FREQTRADE_HOME/freqtrade"
VENV_DIR="$FREQTRADE_HOME/freqtrade_env"
SECRETS_DIR="$FREQTRADE_HOME/.secrets"
LOGFILE="/tmp/ubuntu_setup_$(date +%Y%m%d_%H%M%S).log"
MAX_RETRIES=3

# Fonction de retry
retry() {
    local n=1
    local max=$MAX_RETRIES
    local delay=5
    while true; do
        "$@" && break || {
            if [[ $n -lt $max ]]; then
                ((n++))
                log_warning "Commande échouée. Tentative $n/$max dans ${delay}s..."
                sleep $delay
            else
                log_error "La commande a échoué après $n tentatives."
                return 1
            fi
        }
    done
}

# Fonction de logging
log() {
    echo -e "${GREEN}[$(date +'%Y-%m-%d %H:%M:%S')]${NC} $1" | tee -a "$LOGFILE"
}

log_error() {
    echo -e "${RED}[ERROR]${NC} $1" | tee -a "$LOGFILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING]${NC} $1" | tee -a "$LOGFILE"
}

log_info() {
    echo -e "${BLUE}[INFO]${NC} $1" | tee -a "$LOGFILE"
}

# Vérifier si on est root
check_root() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Ce script ne doit pas être exécuté en tant que root"
        log_error "Il utilise sudo quand nécessaire"
        exit 1
    fi
}

# Nettoyer les anciens logs
cleanup_logs() {
    log_info "Nettoyage des anciens logs..."
    sudo find /tmp -name "ubuntu_setup_*.log" -mtime +7 -delete 2>/dev/null || true
    chmod 600 "$LOGFILE"  # Sécuriser le fichier de log
}

# Créer un utilisateur dédié pour Freqtrade
create_freqtrade_user() {
    log "👤 Création de l'utilisateur dédié $FREQTRADE_USER..."
    
    if ! id "$FREQTRADE_USER" &>/dev/null; then
        sudo useradd -m -s /bin/bash -G docker "$FREQTRADE_USER"
        
        # Créer les répertoires nécessaires
        sudo mkdir -p "$SECRETS_DIR"
        sudo mkdir -p "$FREQTRADE_DIR"
        sudo mkdir -p "$VENV_DIR"
        
        # Définir les permissions
        sudo chown -R "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_HOME"
        sudo chmod 700 "$SECRETS_DIR"
        
        log "✅ Utilisateur $FREQTRADE_USER créé"
    else
        log_info "Utilisateur $FREQTRADE_USER existe déjà"
        # Vérifier les permissions
        sudo chown -R "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_HOME" 2>/dev/null || true
        sudo chmod 700 "$SECRETS_DIR" 2>/dev/null || true
    fi
}

# 1️⃣ Configuration du clavier AZERTY
configure_keyboard() {
    log "🎹 Configuration du clavier AZERTY..."
    
    # Configuration locale
    sudo tee /etc/default/keyboard > /dev/null <<EOF
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF

    # Appliquer la configuration
    sudo setupcon -k --force || true
    sudo localectl set-keymap fr || true
    
    log "✅ Clavier AZERTY configuré"
}

# 2️⃣ Mise à jour du système avec retry
update_system() {
    log "🔄 Mise à jour du système..."
    
    retry sudo apt update
    retry sudo apt upgrade -y
    sudo apt autoremove -y
    sudo apt autoclean
    
    log "✅ Système mis à jour"
}

# 3️⃣ Installation des outils système essentiels
install_essential_tools() {
    log "🛠️ Installation des outils système essentiels..."
    
    retry sudo apt install -y \
        build-essential \
        curl \
        wget \
        unzip \
        zip \
        tar \
        git \
        htop \
        tmux \
        screen \
        ncdu \
        tree \
        mc \
        vim \
        nano \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        jq
    
    log "✅ Outils essentiels installés"
}

# 4️⃣ Gestion de paquets et versions Python
install_package_managers() {
    log "📦 Installation des gestionnaires de paquets..."
    
    # Snap est déjà installé sur Ubuntu 24.04
    sudo snap refresh
    
    # Installation complète des dépendances pour compiler Python
    retry sudo apt install -y \
        make \
        build-essential \
        libssl-dev \
        zlib1g-dev \
        libbz2-dev \
        libreadline-dev \
        libsqlite3-dev \
        wget \
        curl \
        llvm \
        libncursesw5-dev \
        libncurses5-dev \
        xz-utils \
        tk-dev \
        libxml2-dev \
        libxmlsec1-dev \
        libffi-dev \
        liblzma-dev \
        python3-openssl
    
    # Installation de pyenv pour l'utilisateur courant ET freqtrade
    install_pyenv_for_user "$USER"
    install_pyenv_for_user "$FREQTRADE_USER"
    
    log "✅ Gestionnaires de paquets installés"
}

install_pyenv_for_user() {
    local target_user="$1"
    local target_home
    
    if [ "$target_user" = "root" ]; then
        target_home="/root"
    else
        target_home="/home/$target_user"
    fi
    
    if [ ! -d "$target_home/.pyenv" ]; then
        log_info "Installation de pyenv pour $target_user..."
        
        if [ "$target_user" = "$USER" ]; then
            curl https://pyenv.run | bash
        else
            sudo -u "$target_user" bash -c 'curl https://pyenv.run | bash'
        fi
        
        # Configuration du shell (idempotente)
        local bashrc="$target_home/.bashrc"
        if [ "$target_user" = "$USER" ]; then
            if ! grep -q 'pyenv init' "$bashrc" 2>/dev/null; then
                {
                    echo ''
                    echo '# Pyenv configuration'
                    echo 'export PYENV_ROOT="$HOME/.pyenv"'
                    echo 'command -v pyenv >/dev/null || export PATH="$PYENV_ROOT/bin:$PATH"'
                    echo 'eval "$(pyenv init -)"'
                } >> "$bashrc"
            fi
        else
            sudo -u "$target_user" bash -c "
                if ! grep -q 'pyenv init' '$bashrc' 2>/dev/null; then
                    cat >> '$bashrc' <<'PYENV_EOF'

# Pyenv configuration
export PYENV_ROOT=\"\$HOME/.pyenv\"
command -v pyenv >/dev/null || export PATH=\"\$PYENV_ROOT/bin:\$PATH\"
eval \"\$(pyenv init -)\"
PYENV_EOF
                fi
            "
        fi
    else
        log_info "pyenv déjà installé pour $target_user"
    fi
}

# 5️⃣ Outils réseau et tests
install_network_tools() {
    log "🌐 Installation des outils réseau..."
    
    retry sudo apt install -y \
        net-tools \
        nmap \
        traceroute \
        iputils-ping \
        openssh-client \
        openssh-server \
        netcat-openbsd \
        dnsutils \
        whois
    
    log "✅ Outils réseau installés"
}

# 6️⃣ Bases de données et stockage
install_databases() {
    log "🗄️ Installation des bases de données..."
    
    # SQLite
    retry sudo apt install -y sqlite3 libsqlite3-dev
    
    # PostgreSQL
    retry sudo apt install -y postgresql postgresql-contrib postgresql-client libpq-dev
    
    # MySQL/MariaDB
    retry sudo apt install -y mariadb-server mariadb-client libmariadb-dev
    
    # Redis
    retry sudo apt install -y redis-server redis-tools
    
    # Démarrer et activer les services
    sudo systemctl enable postgresql
    sudo systemctl start postgresql
    sudo systemctl enable mariadb
    sudo systemctl start mariadb
    sudo systemctl enable redis-server
    sudo systemctl start redis-server
    
    log "✅ Bases de données installées"
}

# 7️⃣ Installation de Python via pyenv
install_python() {
    log "🐍 Installation de Python $PYTHON_VERSION via pyenv..."
    
    install_python_for_user "$USER"
    install_python_for_user "$FREQTRADE_USER"
    
    log "✅ Python $PYTHON_VERSION installé pour tous les utilisateurs"
}

install_python_for_user() {
    local target_user="$1"
    local target_home
    
    if [ "$target_user" = "root" ]; then
        target_home="/root"
    else
        target_home="/home/$target_user"
    fi
    
    # Commandes pour l'utilisateur spécifique
    if [ "$target_user" = "$USER" ]; then
        # Charger pyenv pour l'utilisateur courant
        export PYENV_ROOT="$target_home/.pyenv"
        export PATH="$PYENV_ROOT/bin:$PATH"
        eval "$(pyenv init -)" 2>/dev/null || true
        
        # Vérifier si Python est déjà installé
        if ! pyenv versions | grep -q "$PYTHON_VERSION"; then
            log_info "Compilation et installation de Python $PYTHON_VERSION pour $target_user..."
            retry pyenv install "$PYTHON_VERSION"
        else
            log_info "Python $PYTHON_VERSION déjà installé pour $target_user"
        fi
        
        # Définir comme version globale
        pyenv global "$PYTHON_VERSION"
        
        # Mettre à jour pip
        pip install --upgrade pip setuptools wheel
    else
        sudo -u "$target_user" bash -c "
            export PYENV_ROOT='$target_home/.pyenv'
            export PATH='\$PYENV_ROOT/bin:\$PATH'
            eval '\$(pyenv init -)' 2>/dev/null || true
            
            if ! pyenv versions | grep -q '$PYTHON_VERSION'; then
                echo 'Installation de Python $PYTHON_VERSION pour $target_user...'
                pyenv install '$PYTHON_VERSION'
            fi
            
            pyenv global '$PYTHON_VERSION'
            pip install --upgrade pip setuptools wheel
        "
    fi
}

# 8️⃣ Développement Python et science des données
install_python_packages() {
    log "📊 Installation des packages Python pour la science des données..."
    
    # Packages de base avec versions pinées pour stabilité
    pip install --upgrade \
        virtualenv \
        virtualenvwrapper \
        'numpy>=1.21.0,<2.0' \
        'pandas>=1.3.0,<2.1' \
        'scipy>=1.7.0,<1.12' \
        'matplotlib>=3.4.0,<3.8' \
        'seaborn>=0.11.0,<0.13' \
        'plotly>=5.0.0,<6.0' \
        'scikit-learn>=1.0.0,<1.4' \
        'jupyter>=1.0.0' \
        'jupyterlab>=3.0.0' \
        'flask>=2.0.0,<3.0' \
        'django>=4.0.0,<5.0' \
        'fastapi>=0.68.0' \
        'uvicorn[standard]>=0.15.0' \
        'requests>=2.25.0' \
        'beautifulsoup4>=4.9.0' \
        'lxml>=4.6.0'
    
    # TensorFlow et PyTorch avec gestion d'erreur
    install_ml_packages
    
    log "✅ Packages Python installés"
}

install_ml_packages() {
    log_info "Installation de TensorFlow et PyTorch..."
    
    # TensorFlow
    if pip install 'tensorflow>=2.10.0,<2.16'; then
        log_info "TensorFlow installé avec succès"
    else
        log_warning "Échec installation TensorFlow - continuons sans"
    fi
    
    # PyTorch (CPU)
    if pip install torch torchvision torchaudio --index-url https://download.pytorch.org/whl/cpu; then
        log_info "PyTorch installé avec succès"
    else
        log_warning "Échec installation PyTorch - continuons sans"
    fi
}

# 9️⃣ Outils de debug et qualité du code
install_dev_tools() {
    log "🔍 Installation des outils de développement..."
    
    pip install \
        black \
        isort \
        'flake8>=4.0.0' \
        'mypy>=0.900' \
        'pytest>=6.0.0' \
        'pytest-cov>=2.10.0' \
        'bandit>=1.7.0' \
        'safety>=1.10.0'
    
    retry sudo apt install -y \
        strace \
        lsof \
        gdb \
        valgrind
    
    log "✅ Outils de développement installés"
}

# 🔟 Docker et virtualisation avec vérifications idempotentes
install_docker() {
    log "🐳 Installation de Docker et Docker Compose..."
    
    # Supprimer les anciennes versions
    sudo apt remove -y docker.io docker-doc docker-compose podman-docker containerd runc 2>/dev/null || true
    
    # Vérifier et ajouter la clé GPG Docker (idempotent)
    if [ ! -f /etc/apt/keyrings/docker.gpg ]; then
        sudo mkdir -p /etc/apt/keyrings
        retry curl -fsSL https://download.docker.com/linux/ubuntu/gpg | sudo gpg --dearmor -o /etc/apt/keyrings/docker.gpg
        sudo chmod a+r /etc/apt/keyrings/docker.gpg
        log_info "Clé GPG Docker ajoutée"
    else
        log_info "Clé GPG Docker déjà présente"
    fi
    
    # Vérifier et ajouter le repository Docker (idempotent)
    if [ ! -f /etc/apt/sources.list.d/docker.list ]; then
        echo \
          "deb [arch=\"$(dpkg --print-architecture)\" signed-by=/etc/apt/keyrings/docker.gpg] https://download.docker.com/linux/ubuntu \
          \"$(. /etc/os-release && echo \"$VERSION_CODENAME\")\" stable" | \
          sudo tee /etc/apt/sources.list.d/docker.list > /dev/null
        log_info "Repository Docker ajouté"
    else
        log_info "Repository Docker déjà présent"
    fi
    
    # Installer Docker
    retry sudo apt update
    retry sudo apt install -y docker-ce docker-ce-cli containerd.io docker-buildx-plugin docker-compose-plugin
    
    # Ajouter les utilisateurs au groupe docker
    sudo usermod -aG docker "$USER"
    sudo usermod -aG docker "$FREQTRADE_USER"
    
    # Démarrer Docker
    sudo systemctl enable docker
    sudo systemctl start docker
    
    # VirtualBox et Vagrant
    retry sudo apt install -y virtualbox vagrant
    
    log "✅ Docker, VirtualBox et Vagrant installés"
}

# 1️⃣1️⃣ Outils "couteaux suisses"
install_swiss_army_tools() {
    log "🔧 Installation des outils utilitaires..."
    
    retry sudo apt install -y \
        ffmpeg \
        imagemagick \
        rsync \
        cron \
        shellcheck \
        parallel \
        pv \
        silversearcher-ag \
        ripgrep \
        fd-find \
        bat \
        exa
    
    # Configuration d'alias utiles (idempotente)
    configure_aliases
    
    log "✅ Outils utilitaires installés"
}

configure_aliases() {
    local alias_block='
# Alias personnalisés Freqtrade Setup
alias ll="ls -alF"
alias la="ls -A"
alias l="ls -CF"
alias grep="grep --color=auto"
alias fgrep="fgrep --color=auto"
alias egrep="egrep --color=auto"
alias ..="cd .."
alias ...="cd ../.."
alias h="history"
alias c="clear"
alias df="df -h"
alias du="du -h"
alias free="free -h"
alias ps="ps aux"
alias top="htop"
alias cat="batcat"
alias ls="exa"
alias find="fdfind"
alias python="python3"
alias pip="pip3"

# Fonctions utiles
function mkcd() { mkdir -p "$1" && cd "$1"; }
function extract() {
    if [ -f $1 ] ; then
        case $1 in
            *.tar.bz2)   tar xjf $1   ;;
            *.tar.gz)    tar xzf $1   ;;
            *.bz2)       bunzip2 $1   ;;
            *.rar)       unrar x $1   ;;
            *.gz)        gunzip $1    ;;
            *.tar)       tar xf $1    ;;
            *.tbz2)      tar xjf $1   ;;
            *.tgz)       tar xzf $1   ;;
            *.zip)       unzip $1     ;;
            *.Z)         uncompress $1;;
            *.7z)        7z x $1      ;;
            *)           echo "'"'"'$1'"'"' ne peut pas être extrait via extract()" ;;
        esac
    else
        echo "'"'"'$1'"'"' n'"'"'est pas un fichier valide"
    fi
}
# Fin alias personnalisés Freqtrade Setup'

    # Ajouter aux deux utilisateurs
    for user in "$USER" "$FREQTRADE_USER"; do
        local user_home
        if [ "$user" = "root" ]; then
            user_home="/root"
        else
            user_home="/home/$user"
        fi
        
        local bashrc="$user_home/.bashrc"
        
        if [ "$user" = "$USER" ]; then
            if ! grep -q "Alias personnalisés Freqtrade Setup" "$bashrc" 2>/dev/null; then
                echo "$alias_block" >> "$bashrc"
            fi
        else
            sudo -u "$user" bash -c "
                if ! grep -q 'Alias personnalisés Freqtrade Setup' '$bashrc' 2>/dev/null; then
                    cat >> '$bashrc' <<'ALIAS_EOF'
$alias_block
ALIAS_EOF
                fi
            "
        fi
    done
}

# 1️⃣2️⃣ Installation et configuration de Freqtrade
install_freqtrade() {
    log "🚀 Installation et configuration de Freqtrade..."
    
    # Tout se fait en tant qu'utilisateur freqtrade
    sudo -u "$FREQTRADE_USER" bash -c "
        export PYENV_ROOT='$FREQTRADE_HOME/.pyenv'
        export PATH='\$PYENV_ROOT/bin:\$PATH'
        eval '\$(pyenv init -)' 2>/dev/null || true
        
        cd '$FREQTRADE_HOME'
        
        # Créer l'environnement virtuel dédié
        if [ ! -d '$VENV_DIR' ]; then
            echo 'Création de l environment virtuel Freqtrade...'
            python -m venv '$VENV_DIR'
        fi
        
        # Activer l'environnement virtuel et installer
        source '$VENV_DIR/bin/activate'
        pip install --upgrade pip setuptools wheel
        pip install 'freqtrade[all]>=2023.1'
        
        # Créer les répertoires
        mkdir -p '$FREQTRADE_DIR'
        cd '$FREQTRADE_DIR'
        
        # Initialiser la configuration si pas encore fait
        if [ ! -f 'config.json' ]; then
            freqtrade create-userdir --userdir .
        fi
    "
    
    # Créer les fichiers de configuration
    create_freqtrade_config
    create_freqtrade_strategy
    create_freqtrade_scripts
    create_systemd_service
    create_freqtrade_documentation
    
    # Sécuriser les permissions
    sudo chown -R "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_HOME"
    sudo chmod 700 "$SECRETS_DIR"
    
    log "✅ Freqtrade installé et configuré avec succès!"
}

create_freqtrade_config() {
    log_info "Création de la configuration Freqtrade..."
    
    # Créer config.json.template (sécurisé)
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/config.json.template' <<'EOF'
{
    \"max_open_trades\": 3,
    \"stake_currency\": \"USDT\",
    \"stake_amount\": 100,
    \"tradable_balance_ratio\": 0.99,
    \"fiat_display_currency\": \"USD\",
    \"dry_run\": true,
    \"dry_run_wallet\": 1000,
    \"cancel_open_orders_on_exit\": false,
    \"trading_mode\": \"spot\",
    \"margin_mode\": \"\",
    \"unfilledtimeout\": {
        \"entry\": 10,
        \"exit\": 10,
        \"exit_timeout_count\": 0,
        \"unit\": \"minutes\"
    },
    \"entry_pricing\": {
        \"price_side\": \"same\",
        \"use_order_book\": true,
        \"order_book_top\": 1,
        \"price_last_balance\": 0.0,
        \"check_depth_of_market\": {
            \"enabled\": false,
            \"bids_to_ask_delta\": 1
        }
    },
    \"exit_pricing\": {
        \"price_side\": \"same\",
        \"use_order_book\": true,
        \"order_book_top\": 1
    },
    \"exchange\": {
        \"name\": \"binance\",
        \"key\": \"YOUR_API_KEY_HERE\",
        \"secret\": \"YOUR_SECRET_KEY_HERE\",
        \"ccxt_config\": {},
        \"ccxt_async_config\": {},
        \"pair_whitelist\": [
            \"BTC/USDT\",
            \"ETH/USDT\",
            \"ADA/USDT\",
            \"DOT/USDT\",
            \"LINK/USDT\"
        ],
        \"pair_blacklist\": []
    },
    \"pairlists\": [
        {
            \"method\": \"StaticPairList\"
        }
    ],
    \"strategy\": \"RSI_MACD_Strategy\",
    \"telegram\": {
        \"enabled\": false,
        \"token\": \"\",
        \"chat_id\": \"\"
    },
    \"api_server\": {
        \"enabled\": false,
        \"listen_ip_address\": \"127.0.0.1\",
        \"listen_port\": 8080,
        \"verbosity\": \"error\",
        \"enable_openapi\": false,
        \"jwt_secret_key\": \"somethingrandom\",
        \"ws_token\": \"sameassecret-but-different\",
        \"CORS_origins\": [],
        \"username\": \"\",
        \"password\": \"\"
    },
    \"bot_name\": \"freqtrade\",
    \"initial_state\": \"running\",
    \"force_entry_enable\": false,
    \"internals\": {
        \"process_throttle_secs\": 5
    }
}
EOF"
    
    # Copier le template vers config.json s'il n'existe pas
    sudo -u "$FREQTRADE_USER" bash -c "
        if [ ! -f '$FREQTRADE_DIR/config.json' ]; then
            cp '$FREQTRADE_DIR/config.json.template' '$FREQTRADE_DIR/config.json'
            chmod 600 '$FREQTRADE_DIR/config.json'
        fi
    "
}

create_freqtrade_strategy() {
    log_info "Installation de la stratégie RSI+MACD optimisée..."
    
    sudo -u "$FREQTRADE_USER" bash -c "
        mkdir -p '$FREQTRADE_DIR/user_data/strategies'
        
        cat > '$FREQTRADE_DIR/user_data/strategies/RSI_MACD_Strategy.py' <<'STRATEGY_EOF'
# pragma pylint: disable=missing-docstring, invalid-name, pointless-string-statement
# flake8: noqa: F401

import numpy as np
import pandas as pd
from pandas import DataFrame
from datetime import datetime
from typing import Optional, Union

from freqtrade.strategy import IStrategy, IntParameter, DecimalParameter
import talib.abstract as ta
import freqtrade.vendor.qtpylib.indicators as qtpylib


class RSI_MACD_Strategy(IStrategy):
    \"\"\"
    Stratégie optimisée combinant RSI et MACD pour les signaux d'entrée et de sortie
    Version allégée pour de meilleures performances
    \"\"\"

    # Strategy interface version
    INTERFACE_VERSION = 3

    # Optimal timeframe for the strategy
    timeframe = '5m'

    # Can this strategy go short?
    can_short: bool = False

    # Minimal ROI designed for the strategy
    minimal_roi = {
        \"60\": 0.01,
        \"30\": 0.02,
        \"0\": 0.04
    }

    # Optimal stoploss designed for the strategy
    stoploss = -0.10

    # Trailing stoploss
    trailing_stop = False

    # Parameters optimisables
    buy_rsi = IntParameter(20, 40, default=30, space=\"buy\", optimize=True)
    sell_rsi = IntParameter(60, 80, default=70, space=\"sell\", optimize=True)

    # Run \"populate_indicators()\" only for new candle
    process_only_new_candles = False

    # These values can be overridden in the config
    use_exit_signal = True
    exit_profit_only = False
    ignore_roi_if_entry_signal = False

    # Number of candles the strategy requires before producing valid signals
    startup_candle_count: int = 30

    # Order configuration
    order_types = {
        'entry': 'limit',
        'exit': 'limit',
        'stoploss': 'market',
        'stoploss_on_exchange': False
    }

    order_time_in_force = {
        'entry': 'GTC',
        'exit': 'GTC'
    }

    plot_config = {
        'main_plot': {
            'tema': {},
        },
        'subplots': {
            \"MACD\": {
                'macd': {'color': 'blue'},
                'macdsignal': {'color': 'red'},
            },
            \"RSI\": {
                'rsi': {'color': 'orange'},
            }
        }
    }

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        \"\"\"
        Ajoute les indicateurs techniques nécessaires
        Version optimisée avec moins d'indicateurs pour de meilleures performances
        \"\"\"

        # RSI
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)

        # MACD
        macd = ta.MACD(dataframe, fastperiod=12, slowperiod=26, signalperiod=9)
        dataframe['macd'] = macd['macd']
        dataframe['macdsignal'] = macd['macdsignal']
        dataframe['macdhist'] = macd['macdhist']

        # Volume SMA pour validation
        dataframe['volume_mean'] = dataframe['volume'].rolling(window=30).mean()

        # Bollinger Bands pour contexte
        bollinger = qtpylib.bollinger_bands(qtpylib.typical_price(dataframe), window=20, stds=2)
        dataframe['bb_lowerband'] = bollinger['lower']
        dataframe['bb_middleband'] = bollinger['mid']
        dataframe['bb_upperband'] = bollinger['upper']

        # TEMA pour trend
        dataframe['tema'] = ta.TEMA(dataframe, timeperiod=9)

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        \"\"\"
        Signaux d'entrée basés sur RSI oversold + MACD crossover + volume
        \"\"\"
        dataframe.loc[
            (
                # Signal: RSI oversold
                (dataframe['rsi'] < self.buy_rsi.value) &
                # Signal: MACD above signal line (momentum positif)
                (dataframe['macd'] > dataframe['macdsignal']) &
                # Volume supérieur à la moyenne
                (dataframe['volume'] > dataframe['volume_mean']) &
                # Prix proche de la bande de Bollinger inférieure
                (dataframe['close'] <= dataframe['bb_lowerband'] * 1.01)
            ),
            'enter_long'] = 1

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        \"\"\"
        Signaux de sortie basés sur RSI overbought + MACD crossunder
        \"\"\"
        dataframe.loc[
            (
                # Signal: RSI overbought
                (dataframe['rsi'] > self.sell_rsi.value) &
                # Signal: MACD below signal line (momentum négatif)
                (dataframe['macd'] < dataframe['macdsignal']) &
                # Volume confirmation
                (dataframe['volume'] > 0)
            ),
            'exit_long'] = 1

        return dataframe
STRATEGY_EOF
    "
}

create_freqtrade_scripts() {
    log_info "Création des scripts de gestion Freqtrade..."
    
    # Script de backtest
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/backtest.sh' <<'BACKTEST_EOF'
#!/bin/bash
# Script de backtesting rapide pour Freqtrade

set -e

# Activer l'environnement virtuel
source $VENV_DIR/bin/activate

# Aller dans le répertoire Freqtrade
cd $FREQTRADE_DIR

# Télécharger les données (derniers 90 jours)
echo \"📊 Téléchargement des données...\"
freqtrade download-data --timerange 20240101- -t 5m --exchange binance

# Lancer le backtest
echo \"🚀 Lancement du backtest...\"
freqtrade backtesting --config config.json --strategy RSI_MACD_Strategy --timerange 20240101- -i 5m

echo \"✅ Backtest terminé!\"
echo \"📊 Résultats sauvegardés dans user_data/backtest_results/\"
BACKTEST_EOF
chmod +x '$FREQTRADE_DIR/backtest.sh'"
    
    # Script de dry-run sécurisé
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/dry_run.sh' <<'DRYRUN_EOF'
#!/bin/bash
# Script de dry-run pour Freqtrade

set -e

# Vérifier que les clés API ne sont pas les valeurs par défaut
if grep -q \"YOUR_API_KEY_HERE\" config.json; then
    echo \"⚠️  ATTENTION: Configurez vos clés API avant d'utiliser ce script!\"
    echo \"   Éditez le fichier config.json et remplacez:\"
    echo \"   - YOUR_API_KEY_HERE par votre vraie clé API\"
    echo \"   - YOUR_SECRET_KEY_HERE par votre vraie clé secrète\"
    echo \"\"
    echo \"   OU utilisez les variables d'environnement:\"
    echo \"   export FREQTRADE_API_KEY='votre_cle'\"
    echo \"   export FREQTRADE_SECRET_KEY='votre_secret'\"
    echo \"\"
    exit 1
fi

# Activer l'environnement virtuel
source $VENV_DIR/bin/activate

# Aller dans le répertoire Freqtrade
cd $FREQTRADE_DIR

echo \"🔄 Démarrage du dry-run...\"
echo \"📊 Mode simulation avec 1000 USDT virtuels\"
echo \"\"

# Lancer le dry-run
freqtrade trade --config config.json --strategy RSI_MACD_Strategy
DRYRUN_EOF
chmod +x '$FREQTRADE_DIR/dry_run.sh'"
    
    # Script d'optimisation
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/hyperopt.sh' <<'HYPEROPT_EOF'
#!/bin/bash
# Script d'optimisation des hyperparamètres pour Freqtrade

set -e

# Activer l'environnement virtuel
source $VENV_DIR/bin/activate

# Aller dans le répertoire Freqtrade
cd $FREQTRADE_DIR

echo \"🎯 Optimisation des hyperparamètres...\"
echo \"⏱️  Cela peut prendre plusieurs heures\"
echo \"\"

# Télécharger les données si nécessaire
freqtrade download-data --timerange 20240101- -t 5m --exchange binance

# Lancer l'optimisation
freqtrade hyperopt \\
    --config config.json \\
    --strategy RSI_MACD_Strategy \\
    --hyperopt-loss SharpeHyperOptLoss \\
    --spaces buy sell \\
    --epochs 100 \\
    -j 4

echo \"✅ Optimisation terminée!\"
echo \"📊 Résultats dans user_data/hyperopt_results/\"
HYPEROPT_EOF
chmod +x '$FREQTRADE_DIR/hyperopt.sh'"

    # Script de configuration des clés API
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/setup_api.sh' <<'APISETUP_EOF'
#!/bin/bash
# Script de configuration sécurisée des clés API

set -e

echo \"🔐 Configuration des clés API Freqtrade\"
echo \"=======================================\"
echo \"\"

# Créer une copie de sauvegarde
cp config.json config.json.backup

# Demander les clés de manière sécurisée
echo \"Exchange supportés: binance, coinbasepro, kraken, bittrex...\"
read -p \"Nom de l'exchange [binance]: \" exchange_name
exchange_name=\${exchange_name:-binance}

echo \"\"
echo \"⚠️  Les clés ne seront pas affichées à l'écran\"
read -s -p \"Clé API: \" api_key
echo \"\"
read -s -p \"Clé secrète: \" secret_key
echo \"\"

# Valider que les clés ne sont pas vides
if [ -z \"\$api_key\" ] || [ -z \"\$secret_key\" ]; then
    echo \"❌ Erreur: Les clés API et secrète sont obligatoires\"
    exit 1
fi

# Remplacer dans le fichier config
sed -i \"s/\\\"name\\\": \\\"binance\\\"/\\\"name\\\": \\\"\$exchange_name\\\"/\" config.json
sed -i \"s/YOUR_API_KEY_HERE/\$api_key/\" config.json
sed -i \"s/YOUR_SECRET_KEY_HERE/\$secret_key/\" config.json

# Sécuriser le fichier
chmod 600 config.json

echo \"\"
echo \"✅ Configuration terminée!\"
echo \"🔒 Fichier config.json sécurisé (permissions 600)\"
echo \"💾 Sauvegarde créée: config.json.backup\"
echo \"\"
echo \"🚀 Vous pouvez maintenant utiliser:\"
echo \"   ./dry_run.sh     # Pour tester en simulation\"
echo \"   ./backtest.sh    # Pour tester sur données historiques\"
APISETUP_EOF
chmod +x '$FREQTRADE_DIR/setup_api.sh'"
}

create_systemd_service() {
    log_info "Création du service systemd pour Freqtrade..."
    
    sudo tee /etc/systemd/system/freqtrade.service > /dev/null <<EOF
[Unit]
Description=Freqtrade Crypto Trading Bot
After=network.target

[Service]
Type=simple
User=$FREQTRADE_USER
Group=$FREQTRADE_USER
WorkingDirectory=$FREQTRADE_DIR
Environment=PATH=$VENV_DIR/bin:/usr/local/bin:/usr/bin:/bin
ExecStartPre=$VENV_DIR/bin/python -c "import freqtrade; print('Freqtrade version:', freqtrade.__version__)"
ExecStart=$VENV_DIR/bin/freqtrade trade --config config.json --strategy RSI_MACD_Strategy
ExecReload=/bin/kill -HUP \$MAINPID
Restart=on-failure
RestartSec=10
StandardOutput=journal
StandardError=journal

# Sécurité
NoNewPrivileges=true
ProtectSystem=strict
ProtectHome=true
ReadWritePaths=$FREQTRADE_HOME
PrivateTmp=true
ProtectKernelTunables=true
ProtectKernelModules=true
ProtectControlGroups=true

[Install]
WantedBy=multi-user.target
EOF

    sudo systemctl daemon-reload
    
    # Créer un script de gestion du service
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/service_control.sh' <<'SERVICE_EOF'
#!/bin/bash
# Script de contrôle du service Freqtrade

case \"\$1\" in
    start)
        echo \"🚀 Démarrage du service Freqtrade...\"
        sudo systemctl start freqtrade
        sudo systemctl status freqtrade --no-pager
        ;;
    stop)
        echo \"🛑 Arrêt du service Freqtrade...\"
        sudo systemctl stop freqtrade
        ;;
    restart)
        echo \"🔄 Redémarrage du service Freqtrade...\"
        sudo systemctl restart freqtrade
        sudo systemctl status freqtrade --no-pager
        ;;
    status)
        sudo systemctl status freqtrade --no-pager
        ;;
    logs)
        echo \"📋 Logs Freqtrade (Ctrl+C pour quitter):\"
        sudo journalctl -u freqtrade -f
        ;;
    enable)
        echo \"⚡ Activation du démarrage automatique...\"
        sudo systemctl enable freqtrade
        ;;
    disable)
        echo \"🔌 Désactivation du démarrage automatique...\"
        sudo systemctl disable freqtrade
        ;;
    *)
        echo \"Usage: \$0 {start|stop|restart|status|logs|enable|disable}\"
        echo \"\"
        echo \"Commandes disponibles:\"
        echo \"  start    - Démarrer Freqtrade\"
        echo \"  stop     - Arrêter Freqtrade\"
        echo \"  restart  - Redémarrer Freqtrade\"
        echo \"  status   - Voir l'état du service\"
        echo \"  logs     - Voir les logs en temps réel\"
        echo \"  enable   - Démarrage automatique\"
        echo \"  disable  - Désactiver démarrage automatique\"
        exit 1
        ;;
esac
SERVICE_EOF
chmod +x '$FREQTRADE_DIR/service_control.sh'"

    log_info "Service systemd Freqtrade créé"
}

create_freqtrade_documentation() {
    log_info "Création de la documentation..."
    
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/README.md' <<'DOC_EOF'
# 🚀 Configuration Freqtrade

## 🔐 SÉCURITÉ - PREMIÈRE ÉTAPE

### Configuration des clés API (OBLIGATOIRE)
```bash
./setup_api.sh
```
Ce script vous guidera pour configurer vos clés API de façon sécurisée.

⚠️ **IMPORTANT** :
- Ne JAMAIS commiter le fichier `config.json` avec vos vraies clés
- Le fichier est automatiquement sécurisé (chmod 600)
- Une sauvegarde `config.json.backup` est créée

## 📊 Scripts disponibles

### Tests et backtests
```bash
./backtest.sh      # Test sur données historiques
./hyperopt.sh      # Optimisation des paramètres
```

### Trading en simulation
```bash
./dry_run.sh       # Simulation temps réel (SÉCURISÉ)
```

### Service en production
```bash
./service_control.sh start     # Démarrer comme service
./service_control.sh stop      # Arrêter le service
./service_control.sh status    # Voir l'état
./service_control.sh logs      # Voir les logs temps réel
./service_control.sh enable    # Démarrage automatique
```

## 🎯 Démarrage rapide

### 1. Tester sans clés API (backtest)
```bash
cd $FREQTRADE_DIR
./backtest.sh
```

### 2. Configurer vos clés et tester en simulation
```bash
./setup_api.sh     # Configurer les clés
./dry_run.sh       # Tester en simulation
```

### 3. Production (ATTENTION: trading réel!)
```bash
# Modifier config.json: \"dry_run\": false
./service_control.sh start
```

## 📈 Stratégie incluse : RSI_MACD_Strategy

### Logique de trading
- **Entrée (Long)** : RSI < 30 + MACD > Signal + Volume élevé + Prix près Bollinger inf.
- **Sortie (Long)** : RSI > 70 + MACD < Signal
- **Stop-loss** : -10%
- **Take-profit** : 4% (immédiat), 2% (30min), 1% (1h)

### Paramètres optimisables
- `buy_rsi` : Seuil RSI d'achat (20-40, défaut: 30)
- `sell_rsi` : Seuil RSI de vente (60-80, défaut: 70)

## ⚙️ Configuration par défaut

```json
{
  \"max_open_trades\": 3,
  \"stake_amount\": 100,
  \"dry_run\": true,
  \"dry_run_wallet\": 1000,
  \"timeframe\": \"5m\"
}
```

## 🔧 Commandes Freqtrade utiles

### Gestion des données
```bash
# Activer l'environnement
source $VENV_DIR/bin/activate
cd $FREQTRADE_DIR

# Télécharger données
freqtrade download-data --timerange 20240101- -t 5m --exchange binance

# Lister stratégies
freqtrade list-strategies

# Analyser résultats
freqtrade show-trades --config config.json
freqtrade plot-dataframe --config config.json --strategy RSI_MACD_Strategy
```

### Monitoring
```bash
# Logs du service
sudo journalctl -u freqtrade -f

# Statut détaillé
freqtrade status --config config.json
```

## 🛡️ Sécurité et bonnes pratiques

### ✅ Recommandations
- **TOUJOURS** tester en `dry_run` d'abord
- Utiliser des montants petits au début
- Surveiller les premiers trades attentivement
- Activer les notifications Telegram (optionnel)
- Faire des backtests réguliers
- Garder des logs de performance

### ⚠️ Avertissements
- Le trading crypto comporte des risques
- Ne tradez jamais plus que ce que vous pouvez perdre
- Les performances passées ne garantissent pas les futures
- Surveillez votre bot régulièrement

### 🔒 Sécurité des clés
- Clés stockées dans `config.json` (permissions 600)
- Possibilité d'utiliser variables d'environnement :
  ```bash
  export FREQTRADE_API_KEY='votre_cle'
  export FREQTRADE_SECRET_KEY='votre_secret'
  ```

## 📚 Ressources utiles

- [Documentation Freqtrade](https://www.freqtrade.io/)
- [Stratégies communautaires](https://github.com/freqtrade/freqtrade-strategies)
- [Discord Freqtrade](https://discord.gg/p7nuUNVfP7)
- [Forum Trading](https://github.com/freqtrade/freqtrade/discussions)

## 🆘 En cas de problème

### Vérifications de base
```bash
# Service actif ?
./service_control.sh status

# Logs d'erreur ?
./service_control.sh logs

# Configuration valide ?
freqtrade show-config --config config.json

# Test de connectivité exchange
freqtrade test-pairlist --config config.json
```

### Commandes de dépannage
```bash
# Réinstaller Freqtrade
source $VENV_DIR/bin/activate
pip install --upgrade freqtrade[all]

# Nettoyer données corrompues
rm -rf user_data/data/*
./backtest.sh  # Retélécharge tout
```
DOC_EOF"
}

# Fonction de nettoyage et optimisation finale
final_cleanup() {
    log "🧹 Nettoyage final du système..."
    
    sudo apt autoremove -y
    sudo apt autoclean
    
    # Nettoyer les caches pip
    pip cache purge 2>/dev/null || true
    
    # Nettoyer les logs système anciens
    sudo journalctl --vacuum-time=7d
    
    log "✅ Nettoyage terminé"
}

# Fonction de vérification post-installation améliorée
verify_installation() {
    log "🔍 Vérification complète de l'installation..."
    
    local issues=0
    
    echo "📋 RÉSUMÉ DE L'INSTALLATION" | tee -a "$LOGFILE"
    echo "============================" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    
    # Vérifications système
    echo "🖥️  SYSTÈME" | tee -a "$LOGFILE"
    echo "----------" | tee -a "$LOGFILE"
    
    # Clavier
    if localectl | grep -q "X11 Layout: fr"; then
        echo "✅ Clavier AZERTY configuré" | tee -a "$LOGFILE"
    else
        echo "❌ Clavier AZERTY non configuré" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    # Python
    if command -v python3 &> /dev/null; then
        echo "✅ Python: $(python3 --version)" | tee -a "$LOGFILE"
    else
        echo "❌ Python non disponible" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    # pyenv
    for user in "$USER" "$FREQTRADE_USER"; do
        local user_home="/home/$user"
        if [ "$user" = "root" ]; then user_home="/root"; fi
        
        if [ -d "$user_home/.pyenv" ]; then
            echo "✅ pyenv installé pour $user" | tee -a "$LOGFILE"
        else
            echo "❌ pyenv manquant pour $user" | tee -a "$LOGFILE"
            ((issues++))
        fi
    done
    
    echo "" | tee -a "$LOGFILE"
    echo "🐳 DOCKER & VIRTUALISATION" | tee -a "$LOGFILE"
    echo "-------------------------" | tee -a "$LOGFILE"
    
    if command -v docker &> /dev/null && docker --version &> /dev/null; then
        echo "✅ Docker: $(docker --version | cut -d' ' -f3 | tr -d ',')" | tee -a "$LOGFILE"
        if groups "$USER" | grep -q docker && groups "$FREQTRADE_USER" | grep -q docker; then
            echo "✅ Utilisateurs dans groupe docker" | tee -a "$LOGFILE"
        else
            echo "⚠️  Utilisateurs pas tous dans groupe docker" | tee -a "$LOGFILE"
        fi
    else
        echo "❌ Docker non installé ou non fonctionnel" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    echo "" | tee -a "$LOGFILE"
    echo "🗄️  BASES DE DONNÉES" | tee -a "$LOGFILE"
    echo "------------------" | tee -a "$LOGFILE"
    
    for service in postgresql mariadb redis-server; do
        if systemctl is-active --quiet "$service"; then
            echo "✅ $service: actif" | tee -a "$LOGFILE"
        else
            echo "⚠️  $service: inactif" | tee -a "$LOGFILE"
        fi
    done
    
    echo "" | tee -a "$LOGFILE"
    echo "🚀 FREQTRADE" | tee -a "$LOGFILE"
    echo "------------" | tee -a "$LOGFILE"
    
    # Utilisateur freqtrade
    if id "$FREQTRADE_USER" &>/dev/null; then
        echo "✅ Utilisateur $FREQTRADE_USER créé" | tee -a "$LOGFILE"
    else
        echo "❌ Utilisateur $FREQTRADE_USER manquant" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    # Répertoires
    if [ -d "$FREQTRADE_DIR" ]; then
        echo "✅ Répertoire Freqtrade: $FREQTRADE_DIR" | tee -a "$LOGFILE"
    else
        echo "❌ Répertoire Freqtrade manquant" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    if [ -d "$VENV_DIR" ]; then
        echo "✅ Environnement virtuel: $VENV_DIR" | tee -a "$LOGFILE"
    else
        echo "❌ Environnement virtuel manquant" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    # Configuration
    if [ -f "$FREQTRADE_DIR/config.json" ]; then
        echo "✅ Configuration Freqtrade présente" | tee -a "$LOGFILE"
        if sudo -u "$FREQTRADE_USER" stat "$FREQTRADE_DIR/config.json" | grep -q "Access: (0600"; then
            echo "✅ Permissions config.json sécurisées" | tee -a "$LOGFILE"
        else
            echo "⚠️  Permissions config.json à vérifier" | tee -a "$LOGFILE"
        fi
    else
        echo "❌ Configuration Freqtrade manquante" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    # Scripts
    local scripts=("backtest.sh" "dry_run.sh" "hyperopt.sh" "setup_api.sh" "service_control.sh")
    local missing_scripts=0
    for script in "${scripts[@]}"; do
        if [ -f "$FREQTRADE_DIR/$script" ] && [ -x "$FREQTRADE_DIR/$script" ]; then
            echo "✅ Script $script présent" | tee -a "$LOGFILE"
        else
            echo "❌ Script $script manquant ou non exécutable" | tee -a "$LOGFILE"
            ((missing_scripts++))
        fi
    done
    
    if [ $missing_scripts -gt 0 ]; then
        ((issues++))
    fi
    
    # Stratégie
    if [ -f "$FREQTRADE_DIR/user_data/strategies/RSI_MACD_Strategy.py" ]; then
        echo "✅ Stratégie RSI_MACD_Strategy installée" | tee -a "$LOGFILE"
    else
        echo "❌ Stratégie manquante" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    # Service systemd
    if [ -f "/etc/systemd/system/freqtrade.service" ]; then
        echo "✅ Service systemd configuré" | tee -a "$LOGFILE"
    else
        echo "❌ Service systemd manquant" | tee -a "$LOGFILE"
        ((issues++))
    fi
    
    echo "" | tee -a "$LOGFILE"
    
    # Résumé final
    if [ $issues -eq 0 ]; then
        echo "🎉 INSTALLATION RÉUSSIE!" | tee -a "$LOGFILE"
        echo "========================" | tee -a "$LOGFILE"
    else
        echo "⚠️  INSTALLATION AVEC $issues PROBLÈME(S)" | tee -a "$LOGFILE"
        echo "==========================================" | tee -a "$LOGFILE"
    fi
    
    echo "" | tee -a "$LOGFILE"
    echo "🎯 PROCHAINES ÉTAPES:" | tee -a "$LOGFILE"
    echo "====================" | tee -a "$LOGFILE"
    echo "1. Redémarrer votre session: logout/login ou 'newgrp docker'" | tee -a "$LOGFILE"
    echo "2. Tester l'installation:" | tee -a "$LOGFILE"
    echo "   sudo -u $FREQTRADE_USER bash -c 'cd $FREQTRADE_DIR && ./backtest.sh'" | tee -a "$LOGFILE"
    echo "3. Configurer vos clés API:" | tee -a "$LOGFILE"
    echo "   sudo -u $FREQTRADE_USER bash -c 'cd $FREQTRADE_DIR && ./setup_api.sh'" | tee -a "$LOGFILE"
    echo "4. Démarrer en mode simulation:" | tee -a "$LOGFILE"
    echo "   sudo -u $FREQTRADE_USER bash -c 'cd $FREQTRADE_DIR && ./dry_run.sh'" | tee -a "$LOGFILE"
    echo "" | tee -a "$LOGFILE"
    echo "📚 Documentation complète: $FREQTRADE_DIR/README.md" | tee -a "$LOGFILE"
    echo "📝 Log détaillé: $LOGFILE" | tee -a "$LOGFILE"
    
    return $issues
}

# Test de connectivité réseau
test_network() {
    log_info "Test de connectivité réseau..."
    
    if ping -c 1 8.8.8.8 &> /dev/null; then
        log_info "✅ Connectivité réseau OK"
    else
        log_warning "❌ Problème de connectivité réseau"
        return 1
    fi
    
    if curl -s --max-time 5 https://api.github.com &> /dev/null; then
        log_info "✅ Accès HTTPS OK"
    else
        log_warning "❌ Problème d'accès HTTPS"
        return 1
    fi
}

# Fonction principale
main() {
    log "🚀 DÉMARRAGE INSTALLATION UBUNTU SERVER 24.04.3 LTS + FREQTRADE"
    log "=================================================================="
    log_info "Version du script: 2.0 (Sécurisée avec utilisateur dédié)"
    log_info "Python cible: $PYTHON_VERSION (compatible TensorFlow/PyTorch)"
    log_info "Utilisateur Freqtrade: $FREQTRADE_USER"
    
    # Vérifications préliminaires
    check_root
    cleanup_logs
    
    # Test réseau
    if ! test_network; then
        log_error "Problème de connectivité. Vérifiez votre connexion Internet."
        exit 1
    fi
    
    # Création utilisateur dédié dès le début
    create_freqtrade_user
    
    # Exécution des étapes principales
    configure_keyboard
    update_system
    install_essential_tools
    install_package_managers
    install_network_tools
    install_databases
    install_python
    install_python_packages
    install_dev_tools
    install_docker
    install_swiss_army_tools
    install_freqtrade
    final_cleanup
    
    # Vérification finale
    if verify_installation; then
        log "🎉 INSTALLATION TERMINÉE AVEC SUCCÈS!"
    else
        log_warning "Installation terminée avec quelques problèmes - consultez les détails ci-dessus"
    fi
    
    echo ""
    echo -e "${GREEN}╔══════════════════════════════════════════════════════════════════════════════════╗${NC}"
    echo -e "${GREEN}║                           🎉 INSTALLATION TERMINÉE! 🎉                           ║${NC}"
    echo -e "${GREEN}╠══════════════════════════════════════════════════════════════════════════════════╣${NC}"
    echo -e "${GREEN}║                                                                                  ║${NC}"
    echo -e "${GREEN}║  ✅ Ubuntu Server 24.04.3 LTS configuré (clavier AZERTY)                       ║${NC}"
    echo -e "${GREEN}║  ✅ Python $PYTHON_VERSION installé avec pyenv                                        ║${NC}"
    echo -e "${GREEN}║  ✅ Environnement de développement complet (Docker, bases de données)          ║${NC}"
    echo -e "${GREEN}║  ✅ Freqtrade installé avec utilisateur dédié '$FREQTRADE_USER'                ║${NC}"
    echo -e "${GREEN}║  ✅ Stratégie RSI+MACD optimisée configurée                                    ║${NC}"
    echo -e "${GREEN}║  ✅ Service systemd prêt pour la production                                    ║${NC}"
    echo -e "${GREEN}║  ✅ Scripts de gestion et documentation complète                               ║${NC}"
    echo -e "${GREEN}║                                                                                  ║${NC}"
    echo -e "${GREEN}║  🎯 DÉMARRAGE RAPIDE:                                                            ║${NC}"
    echo -e "${GREEN}║     1. newgrp docker  # Recharger les groupes                                   ║${NC}"
    echo -e "${GREEN}║     2. sudo -u $FREQTRADE_USER bash -c 'cd $FREQTRADE_DIR && ./backtest.sh'           ║${NC}"
    echo -e "${GREEN}║     3. sudo -u $FREQTRADE_USER bash -c 'cd $FREQTRADE_DIR && ./setup_api.sh'          ║${NC}"
    echo -e "${GREEN}║                                                                                  ║${NC}"
    echo -e "${GREEN}║  📁 Répertoires:                                                                ║${NC}"
    echo -e "${GREEN}║     • Freqtrade: $FREQTRADE_DIR                                        ║${NC}"
    echo -e "${GREEN}║     • Venv Python: $VENV_DIR                                    ║${NC}"
    echo -e "${GREEN}║     • Secrets: $SECRETS_DIR (chmod 700)                                ║${NC}"
    echo -e "${GREEN}║                                                                                  ║${NC}"
    echo -e "${GREEN}║  📖 Documentation: $FREQTRADE_DIR/README.md                            ║${NC}"
    echo -e "${GREEN}║  📋 Log complet: $LOGFILE                         ║${NC}"
    echo -e "${GREEN}╚══════════════════════════════════════════════════════════════════════════════════╝${NC}"
}

# Gestion des erreurs avec contexte
trap 'log_error "Erreur ligne $LINENO dans la fonction ${FUNCNAME[1]:-main} - Code: $?"' ERR

# Gestion des signaux pour nettoyage
cleanup_on_exit() {
    local exit_code=$?
    if [ $exit_code -ne 0 ]; then
        log_error "Script interrompu avec le code $exit_code"
        log_info "Log complet disponible dans: $LOGFILE"
    fi
    exit $exit_code
}
trap cleanup_on_exit EXIT INT TERM

# Vérification des prérequis système
check_system_requirements() {
    log_info "Vérification des prérequis système..."
    
    # Vérifier Ubuntu version
    if ! grep -q "24.04" /etc/os-release; then
        log_warning "Ce script est optimisé pour Ubuntu 24.04. Votre version:"
        cat /etc/os-release | grep VERSION_ID
    fi
    
    # Vérifier espace disque (minimum 10GB)
    local available_space=$(df / | tail -1 | awk '{print $4}')
    local min_space=10485760  # 10GB en KB
    
    if [ "$available_space" -lt "$min_space" ]; then
        log_error "Espace disque insuffisant. Minimum requis: 10GB"
        log_error "Espace disponible: $((available_space / 1024 / 1024))GB"
        exit 1
    fi
    
    # Vérifier RAM (minimum 2GB)
    local total_ram=$(free -k | grep MemTotal | awk '{print $2}')
    local min_ram=2097152  # 2GB en KB
    
    if [ "$total_ram" -lt "$min_ram" ]; then
        log_warning "RAM faible détectée: $((total_ram / 1024 / 1024))GB"
        log_warning "Minimum recommandé: 2GB. Performances possiblement dégradées."
    fi
    
    log_info "✅ Prérequis système vérifiés"
}

# Point d'entrée du script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    # Vérifier les prérequis avant de commencer
    check_system_requirements
    
    # Lancer l'installation principale
    main "$@"
fi