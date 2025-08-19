#!/bin/bash

# Script d'installation idempotent Freqtrade pour Ubuntu Server 24.04.3 LTS
# Auteur: Assistant Claude
# Version: 1.0
# Description: Installation complète d'un environnement de développement Python et Freqtrade

set -euo pipefail  # Arrêt du script en cas d'erreur

# Couleurs pour les logs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m' # No Color

# Variables globales
FREQTRADE_DIR="$HOME/freqtrade"
VENV_DIR="$FREQTRADE_DIR/venv"
CONFIG_DIR="$FREQTRADE_DIR/user_data"
PYTHON_VERSION="3.11"
LOG_FILE="/tmp/freqtrade_setup.log"

# Fonction de logging
log() {
    echo -e "${GREEN}[$(date '+%Y-%m-%d %H:%M:%S')] $1${NC}" | tee -a "$LOG_FILE"
}

log_warning() {
    echo -e "${YELLOW}[WARNING] $1${NC}" | tee -a "$LOG_FILE"
}

log_error() {
    echo -e "${RED}[ERROR] $1${NC}" | tee -a "$LOG_FILE"
}

log_info() {
    echo -e "${BLUE}[INFO] $1${NC}" | tee -a "$LOG_FILE"
}

# Vérification des droits root/sudo
check_sudo() {
    if [[ $EUID -eq 0 ]]; then
        log_error "Ce script ne doit PAS être exécuté en tant que root!"
        log_error "Exécutez-le avec votre utilisateur normal (sudo sera appelé automatiquement)"
        exit 1
    fi
    
    if ! sudo -n true 2>/dev/null; then
        log_info "Vérification des droits sudo..."
        sudo echo "Droits sudo confirmés"
    fi
}

# 1. Configuration du clavier AZERTY système
configure_azerty() {
    log "=== Configuration du clavier AZERTY de façon permanente ==="
    
    # Configuration pour le système actuel
    if ! sudo localectl status | grep -q "VC Keymap: fr"; then
        log_info "Configuration du clavier virtuel console en AZERTY"
        sudo localectl set-keymap fr
    else
        log_info "Clavier virtuel console déjà configuré en AZERTY"
    fi
    
    # Configuration pour X11 (si présent)
    if ! sudo localectl status | grep -q "X11 Layout: fr"; then
        log_info "Configuration du clavier X11 en AZERTY"
        sudo localectl set-x11-keymap fr
    else
        log_info "Clavier X11 déjà configuré en AZERTY"
    fi
    
    # Configuration du layout par défaut dans /etc/default/keyboard
    if ! sudo grep -q "XKBLAYOUT=\"fr\"" /etc/default/keyboard 2>/dev/null; then
        log_info "Mise à jour de /etc/default/keyboard"
        sudo tee /etc/default/keyboard > /dev/null <<EOF
XKBMODEL="pc105"
XKBLAYOUT="fr"
XKBVARIANT=""
XKBOPTIONS=""
BACKSPACE="guess"
EOF
    else
        log_info "/etc/default/keyboard déjà configuré"
    fi
    
    # Application immédiate pour la session courante
    sudo loadkeys fr 2>/dev/null || true
    
    log "Configuration clavier AZERTY terminée"
}

# 2. Mise à jour système et installation des outils réseau/utilitaires
update_system_and_install_tools() {
    log "=== Mise à jour du système et installation des outils ==="
    
    # Mise à jour des paquets
    log_info "Mise à jour de la liste des paquets..."
    sudo apt update
    
    log_info "Mise à niveau du système..."
    sudo DEBIAN_FRONTEND=noninteractive apt upgrade -y
    
    # Installation des outils réseau essentiels
    log_info "Installation des outils réseau et utilitaires système..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        net-tools iproute2 iputils-ping traceroute \
        curl wget netcat-openbsd nmap \
        tcpdump wireshark-common tshark \
        dnsutils whois telnet ftp \
        iftop nethogs iotop \
        openssh-client openssh-server \
        ufw fail2ban \
        htop btop tree \
        vim nano emacs-nox \
        tmux screen \
        git git-lfs \
        build-essential \
        software-properties-common \
        apt-transport-https \
        ca-certificates \
        gnupg \
        lsb-release \
        zip unzip \
        jq \
        rsync \
        cron \
        logrotate \
        sysstat \
        strace \
        lsof \
        psmisc \
        mtr-tiny \
        socat \
        ncdu \
        parallel
    
    # Outils de développement supplémentaires
    log_info "Installation des outils de développement..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        gcc g++ make \
        libc6-dev \
        pkg-config \
        autoconf automake \
        cmake \
        valgrind \
        gdb \
        lldb
        
    log "Installation des outils système terminée"
}

# 3. Installation de Python optimisé pour Freqtrade
install_python_dev_environment() {
    log "=== Installation de Python $PYTHON_VERSION et environnement de développement ==="
    
    # Installation de Python et des dépendances de développement
    log_info "Installation de Python $PYTHON_VERSION et dépendances..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        python$PYTHON_VERSION \
        python$PYTHON_VERSION-dev \
        python$PYTHON_VERSION-venv \
        python3-pip \
        python3-setuptools \
        python3-wheel \
        python3-distutils \
        libpython$PYTHON_VERSION-dev
    
    # Installation des dépendances système pour les packages Python scientifiques
    log_info "Installation des dépendances système pour packages scientifiques..."
    sudo DEBIAN_FRONTEND=noninteractive apt install -y \
        libatlas-base-dev \
        libblas-dev \
        liblapack-dev \
        libopenblas-dev \
        gfortran \
        libhdf5-dev \
        libxml2-dev \
        libxslt1-dev \
        zlib1g-dev \
        libjpeg-dev \
        libpng-dev \
        libfreetype6-dev \
        libffi-dev \
        libssl-dev \
        libsqlite3-dev \
        liblzma-dev \
        libbz2-dev \
        libreadline-dev \
        libncurses5-dev \
        libncursesw5-dev
    
    # Mise à jour de pip système
    if ! python$PYTHON_VERSION -m pip --version &>/dev/null; then
        log_info "Installation/mise à jour de pip..."
        wget -O get-pip.py https://bootstrap.pypa.io/get-pip.py
        python$PYTHON_VERSION get-pip.py --user
        rm get-pip.py
    fi
    
    # Mise à jour de pip
    python$PYTHON_VERSION -m pip install --user --upgrade pip setuptools wheel
    
    log "Installation Python terminée"
}

# 4. Création de l'environnement virtuel et installation de Freqtrade
install_freqtrade() {
    log "=== Installation de Freqtrade dans environnement virtuel ==="
    
    # Création du répertoire Freqtrade s'il n'existe pas
    if [[ ! -d "$FREQTRADE_DIR" ]]; then
        log_info "Création du répertoire Freqtrade: $FREQTRADE_DIR"
        mkdir -p "$FREQTRADE_DIR"
    else
        log_info "Répertoire Freqtrade existe déjà: $FREQTRADE_DIR"
    fi
    
    cd "$FREQTRADE_DIR"
    
    # Création de l'environnement virtuel s'il n'existe pas
    if [[ ! -d "$VENV_DIR" ]]; then
        log_info "Création de l'environnement virtuel Python..."
        python$PYTHON_VERSION -m venv "$VENV_DIR"
    else
        log_info "Environnement virtuel existe déjà"
    fi
    
    # Activation de l'environnement virtuel
    source "$VENV_DIR/bin/activate"
    
    # Mise à jour des outils de base dans le venv
    log_info "Mise à jour des outils de base dans l'environnement virtuel..."
    pip install --upgrade pip setuptools wheel
    
    # Installation de Freqtrade
    if ! pip show freqtrade &>/dev/null; then
        log_info "Installation de Freqtrade dernière version stable..."
        pip install freqtrade[all]
    else
        log_info "Mise à jour de Freqtrade..."
        pip install --upgrade freqtrade[all]
    fi
    
    # Installation des packages Python scientifiques essentiels
    log_info "Installation des packages Python pour l'analyse et ML..."
    pip install --upgrade \
        numpy pandas scipy \
        matplotlib seaborn plotly \
        scikit-learn \
        jupyter jupyterlab \
        requests aiohttp \
        beautifulsoup4 \
        python-dateutil \
        pytz \
        colorama \
        tqdm \
        psutil \
        pyyaml \
        toml \
        click \
        rich
    
    # Installation des dépendances FreqAI si pas déjà présentes
    log_info "Installation des dépendances FreqAI..."
    pip install --upgrade \
        torch \
        scikit-learn \
        joblib \
        optuna \
        gymnasium \
        stable-baselines3
    
    log "Installation Freqtrade terminée"
}

# 5. Configuration initiale de Freqtrade avec FreqAI
configure_freqtrade() {
    log "=== Configuration initiale de Freqtrade avec FreqAI ==="
    
    cd "$FREQTRADE_DIR"
    source "$VENV_DIR/bin/activate"
    
    # Création de la configuration utilisateur s'il n'existe pas
    if [[ ! -d "$CONFIG_DIR" ]]; then
        log_info "Initialisation de la configuration Freqtrade..."
        freqtrade create-userdir --userdir "$CONFIG_DIR"
    else
        log_info "Répertoire de configuration utilisateur existe déjà"
    fi
    
    # Création du fichier de configuration principal s'il n'existe pas
    if [[ ! -f "$CONFIG_DIR/config.json" ]]; then
        log_info "Création du fichier de configuration Freqtrade avec FreqAI..."
        
        cat > "$CONFIG_DIR/config.json" <<'EOF'
{
    "max_open_trades": 10,
    "stake_currency": "USDT",
    "stake_amount": "unlimited",
    "tradable_balance_ratio": 0.99,
    "fiat_display_currency": "EUR",
    "dry_run": true,
    "dry_run_wallet": 1000,
    "cancel_open_orders_on_exit": false,
    "trading_mode": "spot",
    "margin_mode": "",
    "unfilledtimeout": {
        "entry": 10,
        "exit": 10,
        "exit_timeout_count": 0,
        "unit": "minutes"
    },
    "entry_pricing": {
        "price_side": "same",
        "use_order_book": true,
        "order_book_top": 1,
        "price_last_balance": 0.0,
        "check_depth_of_market": {
            "enabled": false,
            "bids_to_ask_delta": 1
        }
    },
    "exit_pricing": {
        "price_side": "same",
        "use_order_book": true,
        "order_book_top": 1
    },
    "exchange": {
        "name": "binance",
        "key": "",
        "secret": "",
        "ccxt_config": {},
        "ccxt_async_config": {},
        "pair_whitelist": [],
        "pair_blacklist": []
    },
    "pairlists": [
        {
            "method": "VolumePairList",
            "number_assets": 50,
            "sort_key": "quoteVolume",
            "min_value": 0,
            "refresh_period": 1800
        },
        {"method": "AgeFilter", "min_days_listed": 10},
        {"method": "PrecisionFilter"},
        {"method": "PriceFilter", 
         "low_price_ratio": 0.01,
         "min_price": 0.00000010,
         "max_price": 0.0
        },
        {"method": "SpreadFilter", "max_spread_ratio": 0.005},
        {"method": "RangeStabilityFilter", "lookback_days": 10, "min_rate_of_change": 0.02, "max_rate_of_change": 0.75},
        {"method": "ShuffleFilter", "seed": 42}
    ],
    "telegram": {
        "enabled": false
    },
    "api_server": {
        "enabled": false
    },
    "bot_name": "freqtrade",
    "initial_state": "running",
    "force_entry_enable": false,
    "internals": {
        "process_throttle_secs": 5
    },
    "freqai": {
        "enabled": true,
        "purge_old_models": 2,
        "train_period_days": 30,
        "backtest_period_days": 7,
        "live_retrain_hours": 0,
        "expiration_hours": 1,
        "identifier": "example",
        "feature_parameters": {
            "include_timeframes": ["5m", "15m", "4h"],
            "include_corr_pairlist": [
                "ETH/USDT",
                "LINK/USDT",
                "BNB/USDT",
                "BTC/USDT"
            ],
            "label_period_candles": 24,
            "include_shifted_candles": 2,
            "DI_threshold": 0.9,
            "weight_factor": 0.9,
            "principal_component_analysis": false,
            "use_SVM_to_remove_outliers": true,
            "plot_feature_importances": 0,
            "svm_params": {
                "shuffle": false,
                "nu": 0.1
            }
        },
        "data_split_parameters": {
            "test_size": 0.33,
            "shuffle": false
        },
        "model_training_parameters": {
            "n_estimators": 800
        },
        "rl_config": {
            "train_cycles": 25,
            "max_training_drawdown_pct": 0.02,
            "cpu_count": 2,
            "model_type": "PPO",
            "policy_type": "MlpPolicy",
            "model_reward_parameters": {
                "rr": 1,
                "profit_aim": 0.025,
                "win_reward_factor": 2
            }
        }
    }
}
EOF
    else
        log_info "Fichier de configuration existe déjà"
    fi
    
    # Création d'une stratégie FreqAI exemple optimisée s'il n'existe pas
    if [[ ! -f "$CONFIG_DIR/strategies/FreqaiExampleStrategy.py" ]]; then
        log_info "Création de la stratégie FreqAI exemple..."
        mkdir -p "$CONFIG_DIR/strategies"
        
        cat > "$CONFIG_DIR/strategies/FreqaiExampleStrategy.py" <<'EOF'
import logging
import numpy as np
import pandas as pd
from functools import reduce
from pandas import DataFrame
from technical import qtpylib

from freqtrade.strategy import (BooleanParameter, CategoricalParameter, DecimalParameter,
                                IStrategy, IntParameter)
import freqtrade.vendor.qtpylib.indicators as qtpylib
import talib.abstract as ta
from freqtrade.persistence import Trade
from datetime import datetime, timedelta

logger = logging.getLogger(__name__)


class FreqaiExampleStrategy(IStrategy):
    """
    Stratégie d'exemple pour FreqAI optimisée pour les cryptomonnaies
    """

    INTERFACE_VERSION = 3
    can_short: bool = False

    minimal_roi = {
        "60": 0.01,
        "30": 0.02,
        "0": 0.04
    }

    plot_config = {
        'main_plot': {
            'tema': {},
            'sar': {'color': 'white'},
        },
        'subplots': {
            "MACD": {
                'macd': {'color': 'blue'},
                'macdsignal': {'color': 'red'},
            },
            "RSI": {
                'rsi': {'color': 'red'},
            }
        }
    }

    process_only_new_candles = True
    stoploss = -0.10
    startup_candle_count: int = 40
    use_exit_signal = True

    # Paramètres optimisables
    buy_rsi = IntParameter(20, 40, default=30, optimize=True)
    sell_rsi = IntParameter(60, 80, default=70, optimize=True)
    short_rsi = IntParameter(60, 80, default=70, optimize=True)
    exit_short_rsi = IntParameter(20, 40, default=30, optimize=True)

    def feature_engineering_expand_all(self, dataframe, period, metadata, **kwargs):
        """
        Cette méthode peut être utilisée par FreqAI pour créer des features supplémentaires.
        Toutes les features définies ici seront automatiquement ajoutées au dataset FreqAI.
        """

        dataframe["%-pct-change"] = dataframe["close"].pct_change()
        dataframe["%-ema-200"] = ta.EMA(dataframe, timeperiod=200)
        dataframe["%-pct-change-ema-200"] = (
            dataframe["%-ema-200"].pct_change()
        )
        dataframe["%-rsi-period"] = ta.RSI(dataframe, timeperiod=period)
        dataframe["%-mfi-period"] = ta.MFI(dataframe, timeperiod=period)
        dataframe["%-adx-period"] = ta.ADX(dataframe, timeperiod=period)
        dataframe["%-sma-200"] = ta.SMA(dataframe, timeperiod=200)
        dataframe["%-ema-50"] = ta.EMA(dataframe, timeperiod=50)
        dataframe["%-ema-200"] = ta.EMA(dataframe, timeperiod=200)

        dataframe["%-tema"] = ta.TEMA(dataframe, timeperiod=9)
        dataframe["%-bb-lowerband"], dataframe["%-bb-middleband"], dataframe["%-bb-upperband"] = ta.BBANDS(dataframe, timeperiod=period)
        dataframe["%-bb-width"] = (
            dataframe["%-bb-upperband"] - dataframe["%-bb-lowerband"]
        ) / dataframe["%-bb-middleband"]
        dataframe["%-close-bb-lower"] = (
            dataframe["close"] / dataframe["%-bb-lowerband"]
        )

        dataframe["%-roc-period"] = ta.ROC(dataframe, timeperiod=period)

        dataframe["%-relative_volume"] = (
            dataframe["volume"] / dataframe["volume"].rolling(period).mean()
        )

        return dataframe

    def feature_engineering_expand_basic(self, dataframe, metadata, **kwargs):
        """
        Features de base toujours calculées
        """

        dataframe["%-pct-change"] = dataframe["close"].pct_change()
        dataframe["%-raw_volume"] = dataframe["volume"]
        dataframe["%-raw_price"] = dataframe["close"]

        return dataframe

    def feature_engineering_standard(self, dataframe, metadata, **kwargs):
        """
        Features standards pour FreqAI
        """

        dataframe["%-day_of_week"] = (dataframe["date"].dt.dayofweek + 1) / 7
        dataframe["%-hour_of_day"] = (dataframe["date"].dt.hour + 1) / 25

        # RSI
        dataframe["%-rsi-14"] = ta.RSI(dataframe, timeperiod=14)
        dataframe["%-rsi-4"] = ta.RSI(dataframe, timeperiod=4)

        # MFI
        dataframe["%-mfi-14"] = ta.MFI(dataframe)

        # EMA
        dataframe["%-ema-10"] = ta.EMA(dataframe, timeperiod=10)
        dataframe["%-ema-21"] = ta.EMA(dataframe, timeperiod=21)
        dataframe["%-ema-50"] = ta.EMA(dataframe, timeperiod=50)
        dataframe["%-ema-200"] = ta.EMA(dataframe, timeperiod=200)

        # SMA
        dataframe["%-sma-9"] = ta.SMA(dataframe, timeperiod=9)
        dataframe["%-sma-21"] = ta.SMA(dataframe, timeperiod=21)
        dataframe["%-sma-50"] = ta.SMA(dataframe, timeperiod=50)

        # Bollinger bands
        bollinger = qtpylib.bollinger_bands(
            qtpylib.typical_price(dataframe), window=20, stds=2
        )
        dataframe["%-bb_lowerband"] = bollinger["lower"]
        dataframe["%-bb_middleband"] = bollinger["mid"]
        dataframe["%-bb_upperband"] = bollinger["upper"]

        dataframe["%-bb_width"] = (
            dataframe["%-bb_upperband"] - dataframe["%-bb_lowerband"]
        ) / dataframe["%-bb_middleband"]
        dataframe["%-close-bb-lower"] = (
            dataframe["close"] / dataframe["%-bb_lowerband"]
        )

        # MACD
        macd = ta.MACD(dataframe)
        dataframe["%-macd"] = macd["macd"]
        dataframe["%-macdsignal"] = macd["macdsignal"]
        dataframe["%-macdhist"] = macd["macdhist"]

        # ADX
        dataframe["%-adx"] = ta.ADX(dataframe)

        return dataframe

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        # Indicateurs de base pour la stratégie
        dataframe['rsi'] = ta.RSI(dataframe)
        dataframe['adx'] = ta.ADX(dataframe)
        dataframe['sar'] = ta.SAR(dataframe)
        dataframe['tema'] = ta.TEMA(dataframe, timeperiod=9)

        # Ajout des features FreqAI
        if self.freqai_info.get('live', False):
            dataframe = self.freqai.start(dataframe, metadata, self)

        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        conditions = []
        dataframe.loc[:, 'enter_tag'] = ''

        # Condition d'entrée basée sur FreqAI
        if self.freqai_info.get('live', False):
            conditions.append(dataframe['&-s_close'] > 0.5)
            dataframe.loc[
                reduce(lambda x, y: x & y, conditions), 'enter_long'] = 1

        # Condition d'entrée de fallback sans FreqAI
        conditions_fallback = [
            (dataframe['rsi'] < self.buy_rsi.value) &
            (dataframe['tema'] > dataframe['tema'].shift(1)) &
            (dataframe['volume'] > 0)
        ]

        if conditions_fallback:
            dataframe.loc[
                reduce(lambda x, y: x & y, conditions_fallback), 'enter_long'] = 1

        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        conditions = []
        dataframe.loc[:, 'exit_tag'] = ''

        # Condition de sortie basée sur FreqAI
        if self.freqai_info.get('live', False):
            conditions.append(dataframe['&-s_close'] < -0.1)
            dataframe.loc[
                reduce(lambda x, y: x & y, conditions), 'exit_long'] = 1

        # Condition de sortie de fallback
        conditions_fallback = [
            (dataframe['rsi'] > self.sell_rsi.value) &
            (dataframe['tema'] < dataframe['tema'].shift(1)) &
            (dataframe['volume'] > 0)
        ]

        if conditions_fallback:
            dataframe.loc[
                reduce(lambda x, y: x & y, conditions_fallback), 'exit_long'] = 1

        return dataframe
EOF
        
    else
        log_info "Stratégie FreqAI existe déjà"
    fi
    
    log "Configuration Freqtrade terminée"
}

# 6. Création des scripts d'aide et documentation
create_helper_scripts() {
    log "=== Création des scripts d'aide ==="
    
    cd "$FREQTRADE_DIR"
    
    # Script d'activation de l'environnement
    if [[ ! -f "activate_freqtrade.sh" ]]; then
        log_info "Création du script d'activation..."
        cat > "activate_freqtrade.sh" <<EOF
#!/bin/bash
# Script d'activation de l'environnement Freqtrade

echo "Activation de l'environnement Freqtrade..."
cd "$FREQTRADE_DIR"
source "$VENV_DIR/bin/activate"

echo "Environnement Freqtrade activé !"
echo "Répertoire de travail: \$(pwd)"
echo "Version Python: \$(python --version)"
echo "Version Freqtrade: \$(freqtrade --version)"
echo ""
echo "Commandes utiles:"
echo "  freqtrade trade --config user_data/config.json --strategy FreqaiExampleStrategy"
echo "  freqtrade download-data --config user_data/config.json --days 30 --timeframe 5m"
echo "  freqtrade backtesting --config user_data/config.json --strategy FreqaiExampleStrategy"
echo "  freqtrade plot-dataframe --config user_data/config.json --strategy FreqaiExampleStrategy"
echo ""
echo "Pour désactiver l'environnement: deactivate"

# Lancement d'un shell interactif
exec \$SHELL
EOF
        chmod +x "activate_freqtrade.sh"
    fi
    
    # Script de configuration de l'API exchange
    if [[ ! -f "configure_exchange.sh" ]]; then
        log_info "Création du script de configuration d'exchange..."
        cat > "configure_exchange.sh" <<'EOF'
#!/bin/bash
# Script de configuration de l'API exchange

CONFIG_FILE="user_data/config.json"
BACKUP_FILE="user_data/config.json.backup.$(date +%Y%m%d_%H%M%S)"

if [[ ! -f "$CONFIG_FILE" ]]; then
    echo "Erreur: Fichier de configuration non trouvé: $CONFIG_FILE"
    exit 1
fi

# Sauvegarde du fichier de configuration
cp "$CONFIG_FILE" "$BACKUP_FILE"
echo "Sauvegarde créée: $BACKUP_FILE"

echo "=== Configuration de l'API Exchange ==="
echo "Exchanges supportés: binance, coinbase, kraken, bittrex, etc."
echo ""

read -p "Nom de l'exchange (par défaut: binance): " exchange_name
exchange_name=${exchange_name:-binance}

read -p "API Key: " api_key
read -s -p "API Secret: " api_secret
echo ""

read -p "Testnet/Sandbox (y/n, par défaut: n): " use_testnet
use_testnet=${use_testnet:-n}

read -p "Mode dry run (y/n, par défaut: y): " dry_run
dry_run=${dry_run:-y}

# Mise à jour du fichier de configuration
python3 -c "
import json

with open('$CONFIG_FILE', 'r') as f:
    config = json.load(f)

config['exchange']['name'] = '$exchange_name'
config['exchange']['key'] = '$api_key'
config['exchange']['secret'] = '$api_secret'

if '$use_testnet' == 'y':
    config['exchange']['sandbox'] = True
else:
    config['exchange'].pop('sandbox', None)

if '$dry_run' == 'y':
    config['dry_run'] = True
else:
    config['dry_run'] = False

with open('$CONFIG_FILE', 'w') as f:
    json.dump(config, f, indent=4)
"

echo ""
echo "Configuration mise à jour avec succès !"
echo "Exchange: $exchange_name"
echo "Dry run: $dry_run"
echo "Testnet: $use_testnet"
echo ""
echo "Vous pouvez maintenant tester la configuration avec:"
echo "  freqtrade list-pairs --config $CONFIG_FILE"
EOF
        chmod +x "configure_exchange.sh"
    fi
    
    # Documentation README
    if [[ ! -f "README.md" ]]; then
        log_info "Création de la documentation README..."
        cat > "README.md" <<'EOF'
# Installation Freqtrade avec FreqAI

## Installation réalisée

✅ **Système configuré:**
- Clavier AZERTY permanent
- Outils réseau et développement complets
- Python 3.11 optimisé
- Environment virtuel Freqtrade

✅ **Freqtrade installé avec:**
- FreqAI activé
- Stratégie d'exemple optimisée
- Configuration automatique des paires
- Environment prêt pour le développement

## Démarrage rapide

### 1. Activation de l'environnement
```bash
cd ~/freqtrade
source venv/bin/activate
# Ou utilisez le script d'aide:
./activate_freqtrade.sh
```

### 2. Configuration de l'API Exchange
```bash
./configure_exchange.sh
```

### 3. Téléchargement des données historiques
```bash
freqtrade download-data --config user_data/config.json --days 30 --timeframes 5m 15m 4h
```

### 4. Test de la stratégie (backtesting)
```bash
freqtrade backtesting --config user_data/config.json --strategy FreqaiExampleStrategy --timeframe 5m
```

### 5. Démarrage du trading
```bash
# Mode dry-run (recommandé pour débuter)
freqtrade trade --config user_data/config.json --strategy FreqaiExampleStrategy

# Mode live (après tests approfondis)
# Modifiez d'abord "dry_run": false dans user_data/config.json
freqtrade trade --config user_data/config.json --strategy FreqaiExampleStrategy
```

## Commandes utiles

### Gestion des données
```bash
# Télécharger des données pour paires spécifiques
freqtrade download-data --config user_data/config.json --pairs BTC/USDT ETH/USDT --days 60

# Lister les paires disponibles
freqtrade list-pairs --config user_data/config.json

# Vérifier les données téléchargées
freqtrade list-data --config user_data/config.json
```

### Backtesting et optimisation
```bash
# Backtesting simple
freqtrade backtesting --config user_data/config.json --strategy FreqaiExampleStrategy

# Backtesting avec période spécifique
freqtrade backtesting --config user_data/config.json --strategy FreqaiExampleStrategy \
  --timerange 20231201-20240301

# Optimisation des paramètres (hyperopt)
freqtrade hyperopt --config user_data/config.json --strategy FreqaiExampleStrategy \
  --hyperopt-loss SharpeHyperOptLoss --epochs 100 --spaces buy sell
```

### Analyse et visualisation
```bash
# Génération de graphiques
freqtrade plot-dataframe --config user_data/config.json --strategy FreqaiExampleStrategy \
  --pairs BTC/USDT --indicators1 ema10 ema21 --indicators2 rsi

# Analyse de profit
freqtrade plot-profit --config user_data/config.json --pairs BTC/USDT ETH/USDT
```

### FreqAI spécifique
```bash
# Entraînement du modèle FreqAI
freqtrade trade --config user_data/config.json --strategy FreqaiExampleStrategy --freqai-backtest-live-models

# Vérification des modèles FreqAI
ls -la user_data/models/
```

## Structure des fichiers

```
~/freqtrade/
├── venv/                           # Environnement virtuel Python
├── user_data/                      # Données et configuration utilisateur
│   ├── config.json                # Configuration principale
│   ├── strategies/                # Stratégies de trading
│   │   └── FreqaiExampleStrategy.py
│   ├── data/                      # Données historiques téléchargées
│   ├── logs/                      # Fichiers de logs
│   ├── models/                    # Modèles FreqAI entraînés
│   └── backtest_results/          # Résultats de backtesting
├── activate_freqtrade.sh          # Script d'activation
├── configure_exchange.sh          # Script configuration API
└── README.md                      # Cette documentation
```

## Configuration FreqAI

La stratégie inclut FreqAI avec les fonctionnalités suivantes:
- **Période d'entraînement**: 30 jours
- **Timeframes multiples**: 5m, 15m, 4h
- **Corrélation avec paires principales**: BTC, ETH, LINK, BNB
- **Algorithmes ML**: RandomForest, SVM pour détection d'outliers
- **Réentraînement**: Manuel (live_retrain_hours: 0)

## Sécurité et bonnes pratiques

### 🔒 Sécurité
- **Démarrez TOUJOURS en mode dry-run**
- Testez exhaustivement avant le trading live
- Utilisez des montants faibles pour les premiers tests
- Surveillez régulièrement les performances

### 📊 Monitoring
```bash
# Vérification des logs en temps réel
tail -f user_data/logs/freqtrade.log

# Monitoring des ressources système
htop
```

### 🛠️ Maintenance
```bash
# Mise à jour de Freqtrade
source venv/bin/activate
pip install --upgrade freqtrade[all]

# Sauvegarde de la configuration
cp user_data/config.json user_data/config_backup_$(date +%Y%m%d).json
```

## Dépannage courant

### Problèmes de connexion API
1. Vérifiez vos clés API dans `user_data/config.json`
2. Vérifiez les permissions de l'API sur l'exchange
3. Testez avec: `freqtrade list-pairs --config user_data/config.json`

### Problèmes FreqAI
1. Vérifiez les logs: `tail -f user_data/logs/freqtrade.log`
2. Réduisez la période d'entraînement si manque de RAM
3. Ajustez `train_period_days` dans la config

### Performance
1. Surveillez l'utilisation CPU/RAM avec `htop`
2. Réduisez `max_open_trades` si système surchargé
3. Utilisez des timeframes plus élevés pour réduire la charge

## Support et ressources

- 📖 [Documentation Freqtrade](https://www.freqtrade.io/en/stable/)
- 🤖 [Guide FreqAI](https://www.freqtrade.io/en/stable/freqai/)
- 💬 [Discord Freqtrade](https://discord.gg/p7nuUNVfP7)
- 📘 [Strategies Repository](https://github.com/freqtrade/freqtrade-strategies)

---

**⚠️ Avertissement**: Le trading de cryptomonnaies présente des risques importants. 
Ne tradez jamais plus que ce que vous pouvez vous permettre de perdre.
EOF
    fi
    
    log "Scripts d'aide créés"
}

# 7. Configuration finale et vérifications
final_configuration() {
    log "=== Configuration finale et vérifications ==="
    
    cd "$FREQTRADE_DIR"
    source "$VENV_DIR/bin/activate"
    
    # Test de l'installation Freqtrade
    log_info "Test de l'installation Freqtrade..."
    if freqtrade --version &>/dev/null; then
        FREQTRADE_VERSION=$(freqtrade --version)
        log "✅ Freqtrade installé: $FREQTRADE_VERSION"
    else
        log_error "❌ Problème avec l'installation Freqtrade"
        exit 1
    fi
    
    # Vérification de la configuration
    log_info "Vérification de la configuration..."
    if freqtrade show-config --config user_data/config.json &>/dev/null; then
        log "✅ Configuration valide"
    else
        log_warning "⚠️  Problème de configuration détecté"
    fi
    
    # Création des répertoires manquants
    mkdir -p user_data/{data,logs,notebooks,models,backtest_results}
    
    # Permissions
    chmod -R 755 "$FREQTRADE_DIR"
    
    log "Configuration finale terminée"
}

# 8. Fonction principale et résumé final
show_final_summary() {
    log "=== INSTALLATION TERMINÉE AVEC SUCCÈS ==="
    log ""
    log "🎉 Votre environnement Freqtrade est prêt !"
    log ""
    log "📍 Emplacement: $FREQTRADE_DIR"
    log "🐍 Python: $(python$PYTHON_VERSION --version 2>/dev/null || echo 'Non testé')"
    log "🤖 Freqtrade: $(cd "$FREQTRADE_DIR" && source "$VENV_DIR/bin/activate" && freqtrade --version 2>/dev/null || echo 'Non testé')"
    log ""
    log "🚀 ÉTAPES SUIVANTES:"
    log "1. Activez l'environnement: cd ~/freqtrade && ./activate_freqtrade.sh"
    log "2. Configurez votre exchange: ./configure_exchange.sh"
    log "3. Téléchargez des données: freqtrade download-data --config user_data/config.json --days 30"
    log "4. Testez avec backtesting: freqtrade backtesting --config user_data/config.json --strategy FreqaiExampleStrategy"
    log "5. Démarrez en dry-run: freqtrade trade --config user_data/config.json --strategy FreqaiExampleStrategy"
    log ""
    log "📚 Documentation complète: ~/freqtrade/README.md"
    log ""
    log "⚠️  IMPORTANT: Démarrez TOUJOURS en mode dry-run pour tester !"
    log ""
    log "🔧 Outils installés:"
    log "   - Tous les outils réseau et développement"
    log "   - Python complet avec packages scientifiques"
    log "   - FreqAI avec stratégie optimisée"
    log "   - Scripts d'aide et documentation"
    log ""
    log "✨ Installation idempotente: vous pouvez relancer ce script sans problème"
    log ""
}

# Fonction principale
main() {
    log "=== DÉBUT D'INSTALLATION FREQTRADE UBUNTU 24.04.3 LTS ==="
    log "Heure de début: $(date)"
    log "Utilisateur: $(whoami)"
    log "Répertoire: $(pwd)"
    log ""
    
    # Vérifications préliminaires
    check_sudo
    
    # Exécution des étapes
    configure_azerty
    update_system_and_install_tools
    install_python_dev_environment
    install_freqtrade
    configure_freqtrade
    create_helper_scripts
    final_configuration
    
    # Résumé final
    show_final_summary
    
    log "=== INSTALLATION TERMINÉE ==="
    log "Heure de fin: $(date)"
    log "Logs sauvegardés dans: $LOG_FILE"
}

# Gestion des signaux pour un arrêt propre
trap 'log_error "Script interrompu par l'utilisateur"; exit 1' INT TERM

# Point d'entrée du script
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
