#!/bin/bash

# =============================================================================
# Script de résolution Code Erreur 6 - Freqtrade Setup
# Corrige les problèmes de permissions et de configuration
# =============================================================================

set -euo pipefail

# Couleurs
RED='\033[0;31m'
GREEN='\033[0;32m'
YELLOW='\033[1;33m'
BLUE='\033[0;34m'
NC='\033[0m'

# Variables
FREQTRADE_USER="freqtrade"
FREQTRADE_HOME="/home/$FREQTRADE_USER"
FREQTRADE_DIR="$FREQTRADE_HOME/freqtrade"
VENV_DIR="$FREQTRADE_HOME/freqtrade_env"
SECRETS_DIR="$FREQTRADE_HOME/.secrets"
CURRENT_USER=$(whoami)

log() { echo -e "${GREEN}[$(date +'%H:%M:%S')]${NC} $1"; }
log_error() { echo -e "${RED}[ERROR]${NC} $1"; }
log_warning() { echo -e "${YELLOW}[WARNING]${NC} $1"; }
log_info() { echo -e "${BLUE}[INFO]${NC} $1"; }

# =============================================================================
# DIAGNOSTIC COMPLET
# =============================================================================

diagnostic_complet() {
    log "🔍 DIAGNOSTIC COMPLET - Code Erreur 6"
    echo "========================================"
    
    # 1. Vérifier l'utilisateur actuel
    echo "👤 Utilisateur actuel: $CURRENT_USER"
    echo "🆔 UID: $(id -u), GID: $(id -g)"
    echo "👥 Groupes: $(groups)"
    echo ""
    
    # 2. Vérifier l'existence de l'utilisateur freqtrade
    if id "$FREQTRADE_USER" &>/dev/null; then
        echo "✅ Utilisateur $FREQTRADE_USER existe"
        echo "🆔 UID freqtrade: $(id -u $FREQTRADE_USER)"
        echo "👥 Groupes freqtrade: $(groups $FREQTRADE_USER)"
    else
        echo "❌ Utilisateur $FREQTRADE_USER n'existe pas"
        return 1
    fi
    echo ""
    
    # 3. Vérifier les répertoires et permissions
    echo "📁 VÉRIFICATION DES RÉPERTOIRES:"
    for dir in "$FREQTRADE_HOME" "$FREQTRADE_DIR" "$VENV_DIR" "$SECRETS_DIR"; do
        if [ -d "$dir" ]; then
            local perms=$(stat -c "%a %U:%G" "$dir" 2>/dev/null || echo "N/A")
            echo "✅ $dir - Permissions: $perms"
        else
            echo "❌ $dir - N'existe pas"
        fi
    done
    echo ""
    
    # 4. Vérifier les fichiers critiques
    echo "📄 VÉRIFICATION DES FICHIERS:"
    local files=(
        "$FREQTRADE_DIR/config.json"
        "$VENV_DIR/bin/activate"
        "$VENV_DIR/bin/python"
        "$VENV_DIR/bin/freqtrade"
    )
    
    for file in "${files[@]}"; do
        if [ -f "$file" ]; then
            local perms=$(stat -c "%a %U:%G" "$file" 2>/dev/null || echo "N/A")
            echo "✅ $file - Permissions: $perms"
        else
            echo "❌ $file - N'existe pas"
        fi
    done
    echo ""
    
    # 5. Vérifier sudo et su
    echo "🔒 VÉRIFICATION ACCÈS SUDO:"
    if sudo -l &>/dev/null; then
        echo "✅ Sudo disponible pour $CURRENT_USER"
    else
        echo "❌ Problème sudo pour $CURRENT_USER"
    fi
    
    if sudo -u "$FREQTRADE_USER" whoami &>/dev/null; then
        echo "✅ Peut exécuter en tant que $FREQTRADE_USER"
    else
        echo "❌ Impossible d'exécuter en tant que $FREQTRADE_USER"
    fi
    echo ""
}

# =============================================================================
# CORRECTIONS AUTOMATIQUES
# =============================================================================

fix_permissions() {
    log "🔧 CORRECTION DES PERMISSIONS"
    
    # Vérifier que l'utilisateur freqtrade existe
    if ! id "$FREQTRADE_USER" &>/dev/null; then
        log_error "Utilisateur $FREQTRADE_USER n'existe pas!"
        log_info "Création de l'utilisateur..."
        sudo useradd -m -s /bin/bash -G docker "$FREQTRADE_USER" || {
            log_error "Impossible de créer l'utilisateur $FREQTRADE_USER"
            return 1
        }
    fi
    
    # Créer les répertoires manquants
    log_info "Création des répertoires manquants..."
    sudo mkdir -p "$FREQTRADE_HOME"
    sudo mkdir -p "$FREQTRADE_DIR"
    sudo mkdir -p "$VENV_DIR"
    sudo mkdir -p "$SECRETS_DIR"
    sudo mkdir -p "$FREQTRADE_DIR/user_data/strategies"
    sudo mkdir -p "$FREQTRADE_DIR/user_data/data"
    
    # Corriger la propriété
    log_info "Correction de la propriété des fichiers..."
    sudo chown -R "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_HOME"
    
    # Corriger les permissions
    log_info "Correction des permissions..."
    sudo chmod 755 "$FREQTRADE_HOME"
    sudo chmod 755 "$FREQTRADE_DIR"
    sudo chmod 755 "$VENV_DIR"
    sudo chmod 700 "$SECRETS_DIR"
    
    # Permissions spéciales pour les scripts
    if [ -d "$FREQTRADE_DIR" ]; then
        sudo find "$FREQTRADE_DIR" -name "*.sh" -exec chmod +x {} \; 2>/dev/null || true
        sudo chown -R "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_DIR"
    fi
    
    log "✅ Permissions corrigées"
}

fix_python_environment() {
    log "🐍 RÉPARATION ENVIRONNEMENT PYTHON"
    
    # Vérifier pyenv pour freqtrade
    if [ ! -d "$FREQTRADE_HOME/.pyenv" ]; then
        log_info "Installation de pyenv pour $FREQTRADE_USER..."
        sudo -u "$FREQTRADE_USER" bash -c "curl https://pyenv.run | bash"
        
        # Configuration bashrc
        sudo -u "$FREQTRADE_USER" bash -c "
            echo '' >> ~/.bashrc
            echo '# Pyenv configuration' >> ~/.bashrc
            echo 'export PYENV_ROOT=\"\$HOME/.pyenv\"' >> ~/.bashrc
            echo 'command -v pyenv >/dev/null || export PATH=\"\$PYENV_ROOT/bin:\$PATH\"' >> ~/.bashrc
            echo 'eval \"\$(pyenv init -)\"' >> ~/.bashrc
        "
    fi
    
    # Recréer l'environnement virtuel si nécessaire
    if [ ! -f "$VENV_DIR/bin/activate" ]; then
        log_info "Recréation de l'environnement virtuel..."
        sudo -u "$FREQTRADE_USER" bash -c "
            export PYENV_ROOT='$FREQTRADE_HOME/.pyenv'
            export PATH='\$PYENV_ROOT/bin:\$PATH'
            eval '\$(pyenv init -)' 2>/dev/null || true
            
            # Utiliser la version Python disponible
            python_version=\$(pyenv global 2>/dev/null || echo '3.11.9')
            if ! pyenv versions | grep -q \"\$python_version\"; then
                python_version=\$(python3 --version | cut -d' ' -f2)
                echo \"Utilisation de Python système: \$python_version\"
                python3 -m venv '$VENV_DIR'
            else
                python -m venv '$VENV_DIR'
            fi
            
            # Installer Freqtrade
            source '$VENV_DIR/bin/activate'
            pip install --upgrade pip setuptools wheel
            pip install 'freqtrade[all]'
        "
    fi
    
    log "✅ Environnement Python réparé"
}

fix_freqtrade_config() {
    log "⚙️ RÉPARATION CONFIGURATION FREQTRADE"
    
    # Créer la configuration de base si manquante
    if [ ! -f "$FREQTRADE_DIR/config.json" ]; then
        log_info "Création de la configuration Freqtrade..."
        sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/config.json' <<'EOF'
{
    \"max_open_trades\": 3,
    \"stake_currency\": \"USDT\",
    \"stake_amount\": 100,
    \"dry_run\": true,
    \"dry_run_wallet\": 1000,
    \"unfilledtimeout\": {
        \"entry\": 10,
        \"exit\": 10,
        \"unit\": \"minutes\"
    },
    \"exchange\": {
        \"name\": \"binance\",
        \"key\": \"YOUR_API_KEY_HERE\",
        \"secret\": \"YOUR_SECRET_KEY_HERE\",
        \"ccxt_config\": {},
        \"pair_whitelist\": [
            \"BTC/USDT\",
            \"ETH/USDT\"
        ]
    },
    \"strategy\": \"SampleStrategy\",
    \"telegram\": {
        \"enabled\": false
    },
    \"api_server\": {
        \"enabled\": false
    },
    \"initial_state\": \"running\"
}
EOF"
        sudo chown "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_DIR/config.json"
        sudo chmod 600 "$FREQTRADE_DIR/config.json"
    fi
    
    # Créer une stratégie de base si manquante
    if [ ! -f "$FREQTRADE_DIR/user_data/strategies/SampleStrategy.py" ]; then
        log_info "Création de la stratégie de base..."
        sudo -u "$FREQTRADE_USER" bash -c "mkdir -p '$FREQTRADE_DIR/user_data/strategies'"
        sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/user_data/strategies/SampleStrategy.py' <<'EOF'
from freqtrade.strategy import IStrategy
from pandas import DataFrame
import talib.abstract as ta

class SampleStrategy(IStrategy):
    INTERFACE_VERSION = 3
    timeframe = '5m'
    stoploss = -0.10
    minimal_roi = {\"0\": 0.1}

    def populate_indicators(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe['rsi'] = ta.RSI(dataframe, timeperiod=14)
        return dataframe

    def populate_entry_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[(dataframe['rsi'] < 30), 'enter_long'] = 1
        return dataframe

    def populate_exit_trend(self, dataframe: DataFrame, metadata: dict) -> DataFrame:
        dataframe.loc[(dataframe['rsi'] > 70), 'exit_long'] = 1
        return dataframe
EOF"
    fi
    
    log "✅ Configuration Freqtrade réparée"
}

# =============================================================================
# ALTERNATIVES D'EXÉCUTION SÉCURISÉES
# =============================================================================

create_safe_execution_methods() {
    log "🛡️ CRÉATION MÉTHODES D'EXÉCUTION SÉCURISÉES"
    
    # Script wrapper sécurisé
    sudo tee /usr/local/bin/freqtrade-wrapper > /dev/null <<'EOF'
#!/bin/bash
# Wrapper sécurisé pour Freqtrade

FREQTRADE_USER="freqtrade"
FREQTRADE_DIR="/home/$FREQTRADE_USER/freqtrade"
VENV_DIR="/home/$FREQTRADE_USER/freqtrade_env"

# Vérifications
if [ ! -d "$FREQTRADE_DIR" ]; then
    echo "❌ Répertoire Freqtrade non trouvé"
    exit 1
fi

if [ ! -f "$VENV_DIR/bin/activate" ]; then
    echo "❌ Environnement virtuel non trouvé"
    exit 1
fi

# Exécution sécurisée
sudo -u "$FREQTRADE_USER" bash -c "
    cd '$FREQTRADE_DIR'
    source '$VENV_DIR/bin/activate'
    freqtrade $*
"
EOF
    
    sudo chmod +x /usr/local/bin/freqtrade-wrapper
    
    # Script de test simple
    sudo -u "$FREQTRADE_USER" bash -c "cat > '$FREQTRADE_DIR/test_simple.sh' <<'EOF'
#!/bin/bash
# Test simple sans sudo

cd /home/freqtrade/freqtrade
source /home/freqtrade/freqtrade_env/bin/activate

echo \"🔍 Test environnement Freqtrade\"
echo \"Python: \$(python --version)\"
echo \"Freqtrade: \$(freqtrade --version)\"
echo \"Config: \$(ls -la config.json)\"

freqtrade show-config --config config.json
EOF"
    
    sudo chmod +x "$FREQTRADE_DIR/test_simple.sh"
    sudo chown "$FREQTRADE_USER:$FREQTRADE_USER" "$FREQTRADE_DIR/test_simple.sh"
    
    log "✅ Méthodes d'exécution sécurisées créées"
}

# =============================================================================
# TESTS DE VALIDATION
# =============================================================================

test_installation() {
    log "🧪 TESTS DE VALIDATION"
    
    log_info "Test 1: Accès utilisateur freqtrade..."
    if sudo -u "$FREQTRADE_USER" whoami &>/dev/null; then
        echo "✅ Accès utilisateur OK"
    else
        echo "❌ Problème accès utilisateur"
        return 1
    fi
    
    log_info "Test 2: Environnement Python..."
    if sudo -u "$FREQTRADE_USER" bash -c "source '$VENV_DIR/bin/activate' && python --version" &>/dev/null; then
        echo "✅ Environnement Python OK"
    else
        echo "❌ Problème environnement Python"
        return 1
    fi
    
    log_info "Test 3: Installation Freqtrade..."
    if sudo -u "$FREQTRADE_USER" bash -c "source '$VENV_DIR/bin/activate' && freqtrade --version" &>/dev/null; then
        echo "✅ Freqtrade installé"
    else
        echo "❌ Problème installation Freqtrade"
        return 1
    fi
    
    log_info "Test 4: Configuration..."
    if sudo -u "$FREQTRADE_USER" bash -c "cd '$FREQTRADE_DIR' && source '$VENV_DIR/bin/activate' && freqtrade show-config --config config.json" &>/dev/null; then
        echo "✅ Configuration valide"
    else
        echo "❌ Problème configuration"
        return 1
    fi
    
    log "✅ Tous les tests passés!"
    return 0
}

# =============================================================================
# MENU PRINCIPAL
# =============================================================================

show_menu() {
    echo ""
    echo -e "${BLUE}🔧 MENU RÉPARATION CODE ERREUR 6${NC}"
    echo "=================================="
    echo "1. 🔍 Diagnostic complet"
    echo "2. 🔧 Réparer permissions"
    echo "3. 🐍 Réparer environnement Python"
    echo "4. ⚙️  Réparer configuration Freqtrade"
    echo "5. 🛡️  Créer méthodes exécution sécurisées"
    echo "6. 🧪 Tester installation"
    echo "7. 🚀 Réparation complète (tout)"
    echo "8. ❌ Quitter"
    echo ""
    read -p "Choisissez une option (1-8): " choice
}

repair_all() {
    log "🚀 RÉPARATION COMPLÈTE"
    echo "====================="
    
    diagnostic_complet
    fix_permissions
    fix_python_environment
    fix_freqtrade_config
    create_safe_execution_methods
    
    echo ""
    log "🧪 Test final..."
    if test_installation; then
        echo ""
        echo -e "${GREEN}🎉 RÉPARATION RÉUSSIE!${NC}"
        echo "===================="
        echo ""
        echo "✅ L'installation est maintenant fonctionnelle"
        echo ""
        echo "🎯 COMMANDES DE TEST:"
        echo "sudo -u freqtrade bash -c 'cd /home/freqtrade/freqtrade && ./test_simple.sh'"
        echo "freqtrade-wrapper --version"
        echo ""
        echo "📚 Scripts disponibles:"
        echo "• /home/freqtrade/freqtrade/test_simple.sh"
        echo "• /usr/local/bin/freqtrade-wrapper"
        echo ""
    else
        echo ""
        echo -e "${RED}❌ PROBLÈMES PERSISTENT${NC}"
        echo "======================"
        echo "Consultez les messages d'erreur ci-dessus"
        echo "Vous pouvez réessayer une réparation ciblée"
    fi
}

main() {
    # Vérifier les permissions d'exécution
    if [[ $EUID -eq 0 ]]; then
        log_error "Ne pas exécuter ce script en root!"
        exit 1
    fi
    
    if ! sudo -v &>/dev/null; then
        log_error "Sudo requis pour ce script"
        exit 1
    fi
    
    while true; do
        show_menu
        case $choice in
            1) diagnostic_complet ;;
            2) fix_permissions ;;
            3) fix_python_environment ;;
            4) fix_freqtrade_config ;;
            5) create_safe_execution_methods ;;
            6) test_installation ;;
            7) repair_all && break ;;
            8) log "Au revoir!"; exit 0 ;;
            *) log_error "Option invalide" ;;
        esac
        echo ""
        read -p "Appuyez sur Entrée pour continuer..."
    done
}

# Point d'entrée
if [[ "${BASH_SOURCE[0]}" == "${0}" ]]; then
    main "$@"
fi
