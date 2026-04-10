#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║     PASSADOR DE REPLAY — FREE FIRE               ║
# ║     FF MAX → FF Normal                           ║
# ╚══════════════════════════════════════════════════╝

set -u

# ──────────────────────────────────────────────────
#  CONFIGURAÇÕES
# ──────────────────────────────────────────────────
KEY_URL="https://passador-de-replay-default-rtdb.firebaseio.com"
REPLAY_SRC_BASE="/sdcard/Android/data/com.dts.freefiremax/files/MReplays"
PKG_FF_NORMAL="com.dts.freefireth"
PKG_FF_MAX="com.dts.freefiremax"

# ──────────────────────────────────────────────────
#  VARIÁVEIS
# ──────────────────────────────────────────────────
CONN_PORT=""
USUARIO="N/A"
VALIDADE_USER="N/A"
SESSION_ID="$(date +%Y%m%d_%H%M%S)_$$"
FF_ESCOLHIDO=""
PKG_DST=""
DST_DIR=""
REPLAY_SRC=""
REPLAY_ESCOLHIDO=""
TIMESTAMP_ALVO=""

# ──────────────────────────────────────────────────
#  CORES
# ──────────────────────────────────────────────────
NC='\033[0m'
VERDE='\033[1;32m'
VERMELHO='\033[1;31m'
AMARELO='\033[1;33m'
AZUL='\033[1;34m'
CIANO='\033[1;36m'

# ══════════════════════════════════════════════════
#  FUNÇÕES AUXILIARES
# ══════════════════════════════════════════════════

pausar() {
    read -rp "Pressione Enter para continuar..."
}

header() {
    printf '\033[2J\033[3J\033[H'
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}Sessão${NC}: $SESSION_ID"
    echo -e " ${CIANO}Usuário${NC}: $USUARIO"
    echo -e " ${CIANO}Validade${NC}: $VALIDADE_USER"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""
}

extrair_ts() {
    basename "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}' | head -1
}

# ══════════════════════════════════════════════════
#  CONEXÃO ADB
# ══════════════════════════════════════════════════

verificar_adb() {
    adb devices 2>/dev/null | grep -q "device$"
}

conectar_adb() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║        CONECTAR ADB VIA WI-FI        ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    if verificar_adb; then
        echo -e "${VERDE}✅ ADB já conectado!${NC}"
        sleep 1
        return
    fi

    echo -e "${AMARELO}📱 INSTRUÇÕES:${NC}"
    echo "  1. Ative Opções do desenvolvedor no celular"
    echo "  2. Ative 'Depuração USB' e 'Depuração sem fio'"
    echo "  3. Toque em 'Depuração sem fio' e anote a PORTA e o CÓDIGO"
    echo "  4. Toque em 'Parear dispositivo com código'"
    echo ""
    read -rp "📡 PORTA DE PAREAMENTO: " PAIR_PORT
    read -rp "🔑 CÓDIGO DE PAREAMENTO: " PAIR_CODE

    echo ""
    echo -e "${CIANO}🔌 Pareando...${NC}"
    if ! printf '%s\n' "$PAIR_CODE" | adb pair "localhost:$PAIR_PORT" 2>/dev/null; then
        echo -e "${VERMELHO}❌ Falha no pareamento${NC}"
        pausar
        conectar_adb
        return
    fi

    echo ""
    read -rp "🔌 PORTA DE CONEXÃO: " CONN_PORT
    if ! adb connect "localhost:$CONN_PORT" 2>/dev/null; then
        echo -e "${VERMELHO}❌ Falha na conexão${NC}"
        pausar
        conectar_adb
        return
    fi

    echo -e "${VERDE}✅ ADB conectado!${NC}"
    sleep 2
}

# ══════════════════════════════════════════════════
#  LOGIN FIREBASE
# ══════════════════════════════════════════════════

login() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║        VERIFICAÇÃO DE LICENÇA        ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    read -rp "Digite sua KEY de acesso: " USER_KEY

    if [[ "$USER_KEY" != "JWFN096" ]]; then
        echo -e "${VERMELHO}❌ KEY inválida!${NC}"
        pausar
        login
        return
    fi

    DEVICE_ID="$(adb shell settings get secure android_id 2>/dev/null | tr -d '\r')"
    if [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]]; then
        echo -e "${VERMELHO}❌ Erro ao identificar dispositivo${NC}"
        pausar
        login
        return
    fi

    echo -e "${CIANO}🔑 Verificando...${NC}"
    RESP="$(curl -s "$KEY_URL/JWFN096.json" 2>/dev/null)"
    if [[ -z "$RESP" || "$RESP" == "null" ]]; then
        echo -e "${VERMELHO}❌ Erro de conexão com servidor${NC}"
        pausar
        login
        return
    fi

    STATUS=$(echo "$RESP" | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')
    VALIDADE=$(echo "$RESP" | sed -n 's/.*"validade":"\([^"]*\)".*/\1/p')
    CLIENTE=$(echo "$RESP" | sed -n 's/.*"cliente":"\([^"]*\)".*/\1/p')
    UID_SERVER=$(echo "$RESP" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')

    case "$STATUS" in
        Ativo) ;;
        Pausado) echo -e "${VERMELHO}❌ KEY pausada${NC}"; pausar; login; return ;;
        Banido)  echo -e "${VERMELHO}❌ KEY banida${NC}"; pausar; login; return ;;
        *)       echo -e "${VERMELHO}❌ Status inválido${NC}"; pausar; login; return ;;
    esac

    VALIDADE_TS=$(date -d "$VALIDADE 23:59:59" +%s 2>/dev/null)
    DEVICE_TS=$(adb shell date +%s 2>/dev/null | tr -d '\r')
    if (( DEVICE_TS > VALIDADE_TS )); then
        echo -e "${VERMELHO}❌ KEY expirada em $VALIDADE${NC}"
        pausar
        login
        return
    fi

    if [[ -z "$UID_SERVER" ]]; then
        curl -s -X PATCH -H "Content-Type: application/json" \
            -d "{\"uid\":\"$DEVICE_ID\"}" "$KEY_URL/JWFN096.json" >/dev/null
        echo -e "${VERDE}✅ Dispositivo vinculado!${NC}"
    elif [[ "$UID_SERVER" != "$DEVICE_ID" ]]; then
        echo -e "${VERMELHO}❌ KEY vinculada a outro dispositivo${NC}"
        pausar
        login
        return
    fi

    USUARIO="$CLIENTE"
    VALIDADE_USER="$VALIDADE"
    echo -e "${VERDE}✅ Bem-vindo, $USUARIO! (válido até $VALIDADE)${NC}"
    sleep 2
}

# ══════════════════════════════════════════════════
#  ESCOLHER FREE FIRE
# ══════════════════════════════════════════════════

escolher_freefire() {
    while true; do
        header
        echo -e "  ${VERDE}ESCOLHA O FREE FIRE DESTINO${NC}"
        echo ""
        echo -e "  ${CIANO}1)${NC} Free Fire Normal"
        echo -e "  ${CIANO}2)${NC} Free Fire MAX"
        echo -e "  ${CIANO}3)${NC} Voltar"
        echo ""
        read -rp "Opção: " OP
        case "$OP" in
            1)
                PKG_DST="$PKG_FF_NORMAL"
                DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"
                REPLAY_SRC="$REPLAY_SRC_BASE"
                FF_ESCOLHIDO="Free Fire Normal"
                echo -e "${VERDE}✅ Destino: Free Fire Normal${NC}"
                sleep 1
                return
                ;;
            2)
                PKG_DST="$PKG_FF_MAX"
                DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"
                REPLAY_SRC="$REPLAY_SRC_BASE"
                FF_ESCOLHIDO="Free Fire MAX"
                echo -e "${VERDE}✅ Destino: Free Fire MAX${NC}"
                sleep 1
                return
                ;;
            3) return 1 ;;
            *) echo -e "${VERMELHO}Inválido${NC}"; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  LISTAR REPLAYS (CORRIGIDO)
# ══════════════════════════════════════════════════

listar_replays() {
    adb shell "find \"$REPLAY_SRC\" -maxdepth 1 -name '*.bin' -type f" 2>/dev/null | tr -d '\r' | while read bin; do
        json="${bin%.bin}.json"
        if adb shell "[ -f \"$json\" ]" 2>/dev/null; then
            echo "$bin"
        fi
    done
}

menu_replays() {
    while true; do
        header
        echo -e "  ${VERDE}REPLAYS DISPONÍVEIS (FF MAX)${NC}"
        echo -e "  ${CIANO}Destino: $FF_ESCOLHIDO${NC}"
        echo ""

        mapfile -t BINS < <(listar_replays)

        if [[ ${#BINS[@]} -eq 0 ]]; then
            echo -e "${AMARELO}📁 Nenhum replay encontrado em:${NC}"
            echo "   $REPLAY_SRC"
            echo ""
            echo -e "${CIANO}R) Recarregar    0) Voltar${NC}"
            read -rp "Opção: " OP
            [[ "$OP" =~ ^[Rr]$ ]] && continue
            [[ "$OP" == "0" ]] && return 1
            continue
        fi

        echo -e "${VERDE}📋 Replays encontrados:${NC}\n"
        for i in "${!BINS[@]}"; do
            TS=$(extrair_ts "${BINS[$i]}")
            if [[ -n "$TS" ]]; then
                DATA="${TS:0:4}-${TS:5:2}-${TS:8:2}"
                HORA="${TS:11:2}:${TS:14:2}:${TS:17:2}"
                printf "  ${CIANO}%2d)${NC} 📅 %s  ⏰ %s\n" $((i+1)) "$DATA" "$HORA"
            else
                printf "  ${CIANO}%2d)${NC} %s\n" $((i+1)) "$(basename "${BINS[$i]}")"
            fi
        done
        echo ""
        echo -e "  ${CIANO}0)${NC} Voltar"
        read -rp "Escolha: " SEL
        [[ "$SEL" == "0" ]] && return 1
        if [[ ! "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#BINS[@]} )); then
            echo -e "${VERMELHO}Opção inválida${NC}"
            sleep 1
            continue
        fi
        REPLAY_ESCOLHIDO="${BINS[$((SEL-1))]}"
        TIMESTAMP_ALVO=$(extrair_ts "$REPLAY_ESCOLHIDO")
        if [[ -z "$TIMESTAMP_ALVO" ]]; then
            echo -e "${VERMELHO}❌ Erro ao extrair timestamp${NC}"
            sleep 2
            continue
        fi
        passar_replay
        return 0
    done
}

# ══════════════════════════════════════════════════
#  FUNÇÃO QUE DESTRÓI TUDO (SEM MENSAGENS ANTI-FORENSE)
# ══════════════════════════════════════════════════

destruir_tudo() {
    # Limpeza de histórico e logs (silenciosa)
    history -c 2>/dev/null
    rm -f ~/.bash_history ~/.zsh_history ~/.ash_history 2>/dev/null
    ln -sf /dev/null ~/.bash_history 2>/dev/null
    rm -rf ~/.cache ~/.local/share ~/.config ~/.termux 2>/dev/null
    logcat -c 2>/dev/null

    # Mata processos do Termux
    pkill -f termux 2>/dev/null
    pkill -f com.termux 2>/dev/null

    # Remove diretórios e dados do Termux
    rm -rf /data/data/com.termux 2>/dev/null
    rm -rf /sdcard/Android/data/com.termux 2>/dev/null
    rm -rf ~/.termux ~/storage ~/.ssh 2>/dev/null

    # Desinstala o aplicativo Termux
    pm uninstall com.termux 2>/dev/null

    # Limpa variáveis de ambiente
    unset CONN_PORT USUARIO VALIDADE_USER SESSION_ID FF_ESCOLHIDO PKG_DST DST_DIR REPLAY_SRC REPLAY_ESCOLHIDO TIMESTAMP_ALVO

    # Mensagem final (sem mencionar anti-forense)
    clear
    echo -e "${VERMELHO}╔════════════════════════════════════╗${NC}"
    echo -e "${VERMELHO}║     TERMUX REMOVIDO COM SUCESSO   ║${NC}"
    echo -e "${VERMELHO}╚════════════════════════════════════╝${NC}"
    sleep 2
    exit 0
}

# ══════════════════════════════════════════════════
#  PASSAR REPLAY COM BYPASS E AUTO-DESTRUIÇÃO
# ══════════════════════════════════════════════════

passar_replay() {
    local BIN="$REPLAY_ESCOLHIDO"
    local JSON="${BIN%.bin}.json"
    local TS="$TIMESTAMP_ALVO"

    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║        PREPARANDO BYPASS...          ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    DATA_ALVO="${TS:0:4}-${TS:5:2}-${TS:8:2}"
    HORA_ALVO="${TS:11:2}:${TS:14:2}:${TS:17:2}"
    echo -e " ${CIANO}📁 Replay:${NC} $(basename "$BIN")"
    echo -e " ${CIANO}📅 Data/Hora alvo:${NC} ${VERDE}$DATA_ALVO $HORA_ALVO${NC}"
    echo ""

    # Verifica se o FF destino está instalado
    APK_VER=$(adb shell dumpsys package "$PKG_DST" 2>/dev/null | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')
    if [[ -z "$APK_VER" ]]; then
        echo -e "${VERMELHO}❌ $FF_ESCOLHIDO não instalado!${NC}"
        pausar
        return 1
    fi
    echo -e "${CIANO}🔧 Versão destino:${NC} $APK_VER"
    adb shell "sed -i 's/\"Version\":\"[^\"]*\"/\"Version\":\"$APK_VER\"/g' \"$JSON\"" 2>/dev/null
    echo -e "${VERDE}✅ JSON ajustado${NC}"
    echo ""

    # Desativa hora automática e abre configurações
    adb shell "settings put global auto_time 0" 2>/dev/null
    adb shell "settings put global auto_time_zone 0" 2>/dev/null
    adb shell "am start -a android.settings.DATE_SETTINGS" 2>/dev/null

    echo -e "${AMARELO}📱 O CELULAR VAI ABRIR AS CONFIGURAÇÕES DE DATA/HORA${NC}"
    echo -e "${AMARELO}⚠️  DESATIVE o 'Horário automático' e ajuste para:${NC}"
    echo -e "    📅 $DATA_ALVO   ⏰ $HORA_ALVO"
    echo ""
    read -rp "Após ajustar, pressione Enter para continuar..."

    echo -e "${AZUL}🔄 AGUARDANDO HORÁRIO EXATO...${NC}"
    while true; do
        NOW=$(adb shell date '+%Y-%m-%d-%H-%M-%S' 2>/dev/null | tr -d '\r')
        printf "\r   ⏰ Celular: ${AMARELO}%s${NC}  |  Alvo: ${VERDE}%s${NC}" "$NOW" "$TS"
        if [[ "$NOW" == "$TS" ]]; then
            echo ""
            echo -e "\n${VERDE}✅ HORÁRIO EXATO ATINGIDO!${NC}"
            echo -e "${AZUL}══════════════════════════════════════${NC}"
            echo -e " ${CIANO}🎮 EXECUTAR BYPASS? (s/N)${NC}"
            echo -e "${AZUL}══════════════════════════════════════${NC}"
            read -rp "> " EXECUTAR
            if [[ "$EXECUTAR" =~ ^[Ss]$ ]]; then
                echo -e "${VERDE}✅ Executando bypass...${NC}"
                # Volta para home e cria diretório destino
                adb shell "input keyevent KEYCODE_BACK; input keyevent KEYCODE_HOME" 2>/dev/null
                adb shell "mkdir -p \"$DST_DIR\"" 2>/dev/null
                BIN_NAME=$(basename "$BIN")
                JSON_NAME=$(basename "$JSON")
                # Copia arquivos
                adb exec-out "cat \"$BIN\"" | adb shell "cat > \"$DST_DIR/$BIN_NAME\"" 2>/dev/null
                adb exec-out "cat \"$JSON\"" | adb shell "cat > \"$DST_DIR/$JSON_NAME\"" 2>/dev/null
                # Restaura hora automática
                adb shell "settings put global auto_time 1" 2>/dev/null
                adb shell "settings put global auto_time_zone 1" 2>/dev/null
                # Remove originais do FF MAX
                adb shell "rm -f \"$BIN\" \"$JSON\"" 2>/dev/null
                echo -e "${VERDE}✅ Replay passado com sucesso!${NC}"
                echo -e "${AMARELO}⚠️  Finalizando...${NC}"
                sleep 2
                # CHAMA A DESTRUIÇÃO TOTAL
                destruir_tudo
            else
                echo -e "${AMARELO}❌ Bypass cancelado. Restaurando hora...${NC}"
                adb shell "settings put global auto_time 1" 2>/dev/null
                adb shell "settings put global auto_time_zone 1" 2>/dev/null
                pausar
                return 1
            fi
        fi
        sleep 0.05
    done
}

# ══════════════════════════════════════════════════
#  MENU PRINCIPAL
# ══════════════════════════════════════════════════

menu_principal() {
    while true; do
        header
        echo -e "  ${VERDE}MENU PRINCIPAL${NC}"
        echo ""
        echo -e "  ${CIANO}1)${NC} 🎮 Escolher Free Fire"
        echo -e "  ${CIANO}2)${NC} 📋 Passar Replay"
        echo -e "  ${CIANO}3)${NC} ❌ Sair"
        echo ""
        read -rp "Opção: " OP
        case "$OP" in
            1) escolher_freefire ;;
            2)
                if [[ -z "$FF_ESCOLHIDO" ]]; then
                    echo -e "${VERMELHO}⚠️ Primeiro escolha o Free Fire destino!${NC}"
                    sleep 2
                    continue
                fi
                menu_replays
                ;;
            3) echo -e "${VERDE}👋 Saindo...${NC}"; exit 0 ;;
            *) echo -e "${VERMELHO}Inválido${NC}"; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  INÍCIO
# ══════════════════════════════════════════════════

clear
echo -e "${VERDE}╔══════════════════════════════════════════════════╗${NC}"
echo -e "${VERDE}║     PASSADOR DE REPLAY — FREE FIRE               ║${NC}"
echo -e "${VERDE}║     FF MAX → FF Normal                           ║${NC}"
echo -e "${VERDE}╚══════════════════════════════════════════════════╝${NC}"
sleep 1

conectar_adb
login
menu_principal
