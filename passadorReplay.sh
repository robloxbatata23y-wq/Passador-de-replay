#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║     PASSADOR DE REPLAY — FREE FIRE               ║
# ║     FF MAX → FF Normal | Detecção automática     ║
# ╚══════════════════════════════════════════════════╝

set -u

# ──────────────────────────────────────────────────
#  CONFIGURAÇÕES — edite antes de usar
# ──────────────────────────────────────────────────
KEY_URL="https://passador-de-replay-default-rtdb.firebaseio.com"

# Pasta de replays do FF MAX (origem — onde o jogo salva)
REPLAY_SRC="/sdcard/Android/data/com.dts.freefiremax/files/MReplays"

# Pacote do FF Normal (destino)
PKG_DST="com.dts.freefireth"
DST_DIR="/sdcard/Android/data/${PKG_DST}/files/MReplays"

# ──────────────────────────────────────────────────
#  VARIÁVEIS DE ESTADO
# ──────────────────────────────────────────────────
CONN_PORT=""
USUARIO="N/A"
VALIDADE_USER="N/A"
APK_VER_DST=""

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
#  UTILITÁRIOS
# ══════════════════════════════════════════════════

pausar() { read -rp "Pressione Enter para continuar..."; }

header() {
    local adb_status
    if adb devices 2>/dev/null | grep -q "device$"; then
        adb_status="${VERDE}Conectado${NC}"
    else
        adb_status="${VERMELHO}Desconectado${NC}"
    fi
    clear
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}Usuário ${NC}: $USUARIO"
    echo -e " ${CIANO}Validade${NC}: $VALIDADE_USER"
    echo -e " ${CIANO}ADB     ${NC}: $(echo -e "$adb_status")"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""
}

# Extrai timestamp do nome do arquivo
# Ex: Replay_2024-06-10-21-30-45_abc.bin → 2024-06-10-21-30-45
extrair_ts() {
    basename "$1" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}'
}

# Lista todos os .bin do FF MAX que têm .json correspondente
listar_replays() {
    adb shell "
        for f in \"$REPLAY_SRC\"/*.bin; do
            [ -f \"\$f\" ] || continue
            j=\"\${f%.bin}.json\"
            [ -f \"\$j\" ] && echo \"\$f\"
        done
    " 2>/dev/null | tr -d '\r'
}

# ══════════════════════════════════════════════════
#  PASSO 1 — CONECTAR ADB
# ══════════════════════════════════════════════════
conectar_adb() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║    CONECTAR ADB VIA WI-FI          ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    if adb devices 2>/dev/null | grep -q "device$"; then
        echo -e "${VERDE}✅ ADB já conectado!${NC}"
        sleep 1; return
    fi

    echo -e "${AMARELO}Ative: Configurações > Opções do desenvolvedor"
    echo -e "       > Depuração sem fio > Parear dispositivo${NC}"
    echo ""

    read -rp "Porta de pareamento : " PAIR_PORT
    read -rp "Código de pareamento: " PAIR_CODE

    printf '%s\n' "$PAIR_CODE" | adb pair "localhost:$PAIR_PORT" || {
        echo -e "${VERMELHO}❌ Falha no pareamento${NC}"; exit 1
    }
    echo ""
    read -rp "Porta de conexão: " CONN_PORT
    adb connect "localhost:$CONN_PORT" || {
        echo -e "${VERMELHO}❌ Falha na conexão${NC}"; exit 1
    }
    adb devices | grep -q "device$" || {
        echo -e "${VERMELHO}❌ Dispositivo não reconhecido${NC}"; exit 1
    }
    echo -e "${VERDE}✅ ADB conectado!${NC}"
    sleep 1
}

# ══════════════════════════════════════════════════
#  PASSO 2 — LOGIN (licença Firebase)
# ══════════════════════════════════════════════════
login() {
    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║    LOGIN POR CHAVE                 ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""

    read -rp "Sua KEY de acesso: " USER_KEY

    DEVICE_ID="$(adb shell settings get secure android_id 2>/dev/null | tr -d '\r')"
    [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]] && {
        echo -e "${VERMELHO}❌ Erro ao obter UID do dispositivo${NC}"; exit 1
    }

    echo -e "${CIANO}🔑 Verificando chave...${NC}"
    RESP="$(curl -s "$KEY_URL/$USER_KEY.json")"
    [[ -z "$RESP" || "$RESP" == "null" ]] && {
        echo -e "${VERMELHO}❌ KEY inválida${NC}"; exit 1
    }

    STATUS="$(echo "$RESP"     | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
    VALIDADE="$(echo "$RESP"   | sed -n 's/.*"validade":"\([^"]*\)".*/\1/p')"
    CLIENTE="$(echo "$RESP"    | sed -n 's/.*"cliente":"\([^"]*\)".*/\1/p')"
    UID_SERVER="$(echo "$RESP" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')"

    case "$STATUS" in
        Ativo)   ;;
        Pausado) echo -e "${VERMELHO}❌ KEY pausada${NC}";    exit 1 ;;
        Banido)  echo -e "${VERMELHO}❌ KEY banida${NC}";     exit 1 ;;
        *)       echo -e "${VERMELHO}❌ Status inválido${NC}"; exit 1 ;;
    esac

    VALIDADE_TS="$(date -d "$VALIDADE 23:59:59" +%s 2>/dev/null)"
    DEVICE_TS="$(adb shell date +%s 2>/dev/null | tr -d '\r')"
    [[ -z "$VALIDADE_TS" ]] && {
        echo -e "${VERMELHO}❌ Data inválida no servidor${NC}"; exit 1
    }
    (( DEVICE_TS > VALIDADE_TS )) && {
        echo -e "${VERMELHO}❌ KEY expirada em $VALIDADE${NC}"; exit 1
    }

    if [[ -z "$UID_SERVER" ]]; then
        curl -s -X PATCH \
            -H "Content-Type: application/json" \
            -d "{\"uid\":\"$DEVICE_ID\"}" \
            "$KEY_URL/$USER_KEY.json" >/dev/null
        echo -e "${VERDE}✅ Dispositivo vinculado!${NC}"
    elif [[ "$UID_SERVER" != "$DEVICE_ID" ]]; then
        echo -e "${VERMELHO}❌ KEY vinculada a outro dispositivo${NC}"; exit 1
    fi

    USUARIO="$CLIENTE"
    VALIDADE_USER="$VALIDADE"
    echo -e "${VERDE}✅ Bem-vindo, $USUARIO! (válido até $VALIDADE)${NC}"
    sleep 2
}

# ══════════════════════════════════════════════════
#  PASSAR REPLAY
#  $1 = caminho completo do .bin no celular
# ══════════════════════════════════════════════════
passar_replay() {
    local BIN="$1"
    local JSON="${BIN%.bin}.json"

    # Extrai timestamp
    local TS
    TS="$(extrair_ts "$BIN")"
    if [[ -z "$TS" ]]; then
        echo -e "${VERMELHO}❌ Timestamp inválido no nome do arquivo${NC}"
        echo    "   Esperado: Replay_YYYY-MM-DD-HH-MM-SS_xxx.bin"
        pausar; return 1
    fi

    # Lê versão do FF Normal instalado
    APK_VER_DST="$(adb shell dumpsys package "$PKG_DST" 2>/dev/null \
        | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')"
    if [[ -z "$APK_VER_DST" ]]; then
        echo -e "${VERMELHO}❌ Free Fire Normal não encontrado no celular${NC}"
        pausar; return 1
    fi

    # Corrige a versão dentro do JSON para bater com o FF Normal
    adb shell \
        "sed -i 's/\"Version\":\"[^\"]*\"/\"Version\":\"$APK_VER_DST\"/g' \"$JSON\"" \
        >/dev/null 2>&1

    clear
    echo -e "${AZUL}╔════════════════════════════════════╗"
    echo -e "║    ⚡ PASSANDO REPLAY               ║"
    echo -e "╚════════════════════════════════════╝${NC}"
    echo ""
    echo -e " Arquivo : ${VERDE}$(basename "$BIN")${NC}"
    echo -e " Versão  : ${VERDE}$APK_VER_DST${NC}"
    echo ""
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e " ${CIANO}📅 Data : ${AMARELO}${TS:0:4}-${TS:5:2}-${TS:8:2}${NC}"
    echo -e " ${CIANO}⏰ Hora : ${AMARELO}${TS:11:2}:${TS:14:2}:${TS:17:2}${NC}"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""
    echo -e "${AMARELO}📲 AJUSTE NO CELULAR AGORA:${NC}"
    echo -e "   Data → ${VERDE}${TS:0:4}-${TS:5:2}-${TS:8:2}${NC}"
    echo -e "   Hora → ${VERDE}${TS:11:2}:${TS:14:2}:${TS:17:2}${NC}"
    echo ""

    # Desativa hora automática e abre configurações de data/hora
    adb shell "settings put global auto_time 0"                   >/dev/null 2>&1
    adb shell "settings put global auto_time_zone 0"             >/dev/null 2>&1
    adb shell "am start -a android.settings.DATE_SETTINGS"       >/dev/null 2>&1

    echo -e "${CIANO}⏳ Ajuste a data/hora e aguarde o segundo exato... (monitorando em 5s)${NC}"
    sleep 5

    # Loop: monitora a hora do celular até bater o segundo exato
    echo -e "${AZUL}🔄 Monitorando hora do celular...${NC}"
    while true; do
        local NOW
        NOW="$(adb shell date '+%Y-%m-%d-%H-%M-%S' 2>/dev/null | tr -d '\r')"
        printf "\r   ⏰ Celular: ${AMARELO}%s${NC}  |  Alvo: ${VERDE}%s${NC}   " "$NOW" "$TS"
        if [[ "$NOW" == "$TS" ]]; then
            echo -e "\n${VERDE}✅ SEGUNDO EXATO! Copiando arquivos...${NC}"
            break
        fi
        sleep 0.2
    done

    # Volta para home e garante pasta de destino
    adb shell "input keyevent KEYCODE_BACK" >/dev/null 2>&1
    adb shell "input keyevent KEYCODE_HOME" >/dev/null 2>&1
    adb shell "mkdir -p \"$DST_DIR\""       >/dev/null 2>&1

    local BIN_DST="$DST_DIR/$(basename "$BIN")"
    local JSON_DST="$DST_DIR/$(basename "$JSON")"

    # Copia .bin e .json para o FF Normal
    adb exec-out "cat \"$BIN\""  | adb shell "cat > \"$BIN_DST\""  2>/dev/null
    adb exec-out "cat \"$JSON\"" | adb shell "cat > \"$JSON_DST\"" 2>/dev/null

    # Restaura hora automática
    adb shell "settings put global auto_time 1"      >/dev/null 2>&1
    adb shell "settings put global auto_time_zone 1" >/dev/null 2>&1

    # Apaga originais do FF MAX
    adb shell "rm -f \"$BIN\" \"$JSON\"" >/dev/null 2>&1

    echo ""
    echo -e "${VERDE}✅ REPLAY PASSADO COM SUCESSO!${NC}"
    echo -e "   FF MAX  → ${CIANO}$(basename "$BIN")${NC}"
    echo -e "   FF Normal → ${VERDE}$DST_DIR${NC}"
    echo ""
    pausar
}

# ══════════════════════════════════════════════════
#  MENU DE ESCOLHA DE REPLAY (manual)
# ══════════════════════════════════════════════════
menu_replays() {
    while true; do
        header

        mapfile -t BINS < <(listar_replays)

        if [[ ${#BINS[@]} -eq 0 ]]; then
            echo -e "${AMARELO}Nenhum replay encontrado em:${NC}"
            echo -e "  $REPLAY_SRC"
            echo ""
            echo "Jogue uma partida no FF MAX e salve o replay."
            echo ""
            echo -e "  ${CIANO}R)${NC} Recarregar"
            echo -e "  ${CIANO}0)${NC} Voltar"
            echo ""
            read -rp "Opção: " OP
            [[ "$OP" =~ ^[Rr]$ ]] && continue
            return
        fi

        echo -e "${VERDE}Replays disponíveis (FF MAX):${NC}"
        echo ""
        for i in "${!BINS[@]}"; do
            local TS DATA HORA
            TS="$(extrair_ts "${BINS[$i]}")"
            if [[ -n "$TS" ]]; then
                DATA="${TS:0:4}-${TS:5:2}-${TS:8:2}"
                HORA="${TS:11:2}:${TS:14:2}:${TS:17:2}"
                printf "  ${CIANO}%2d)${NC} 📅 %s  ⏰ %s\n" $((i+1)) "$DATA" "$HORA"
            else
                printf "  ${CIANO}%2d)${NC} %s\n" $((i+1)) "$(basename "${BINS[$i]}")"
            fi
        done

        echo ""
        echo -e "  ${CIANO} R)${NC} Recarregar"
        echo -e "  ${CIANO} 0)${NC} Voltar"
        echo ""
        read -rp "Escolha o replay: " SEL

        [[ "$SEL" =~ ^[Rr]$ ]] && continue
        [[ "$SEL" == "0" ]]    && return

        if ! [[ "$SEL" =~ ^[0-9]+$ ]] || (( SEL < 1 || SEL > ${#BINS[@]} )); then
            echo -e "${VERMELHO}Opção inválida${NC}"; sleep 1; continue
        fi

        passar_replay "${BINS[$((SEL-1))]}"
    done
}

# ══════════════════════════════════════════════════
#  MONITORAMENTO AUTOMÁTICO PÓS-PARTIDA
#
#  Tira um snapshot dos replays existentes ao entrar.
#  A cada 2s verifica se apareceu arquivo novo.
#  Quando detecta, pergunta se quer passar agora.
# ══════════════════════════════════════════════════
monitor_automatico() {
    header
    echo -e "${VERDE}📡 MONITORAMENTO AUTOMÁTICO ATIVO${NC}"
    echo ""
    echo -e " Origem : ${CIANO}$REPLAY_SRC${NC}"
    echo -e " Destino: ${CIANO}$DST_DIR${NC}"
    echo ""
    echo -e "${AMARELO}⚠️  Jogue sua partida no FF MAX e salve o replay."
    echo -e "    O script detecta automaticamente ao terminar.${NC}"
    echo ""
    echo -e "${CIANO}Para parar: Ctrl+C${NC}"
    echo ""

    # Snapshot dos replays já existentes
    declare -A JA_EXISTIA
    while IFS= read -r f; do
        [[ -n "$f" ]] && JA_EXISTIA["$f"]=1
    done < <(listar_replays)

    echo -e "${AZUL}🔄 Aguardando nova partida...${NC}"

    while true; do
        # Verifica conexão ADB
        if ! adb devices 2>/dev/null | grep -q "device$"; then
            echo -e "\n${VERMELHO}❌ ADB desconectado! Reconectando...${NC}"
            adb connect "localhost:$CONN_PORT" 2>/dev/null
            sleep 3; continue
        fi

        # Compara lista atual com snapshot inicial
        while IFS= read -r NOVO; do
            [[ -z "$NOVO" ]]                   && continue
            [[ -n "${JA_EXISTIA[$NOVO]:-}" ]]  && continue

            # Arquivo novo detectado!
            local TS DATA HORA
            TS="$(extrair_ts "$NOVO")"
            DATA="${TS:0:4}-${TS:5:2}-${TS:8:2}"
            HORA="${TS:11:2}:${TS:14:2}:${TS:17:2}"

            echo ""
            echo -e "${VERDE}╔════════════════════════════════════╗"
            echo -e "║  🎮 NOVA PARTIDA DETECTADA!        ║"
            echo -e "╚════════════════════════════════════╝${NC}"
            echo ""
            echo -e " 📅 Data    : ${AMARELO}$DATA${NC}"
            echo -e " ⏰ Hora    : ${AMARELO}$HORA${NC}"
            echo -e " 📁 Arquivo : ${CIANO}$(basename "$NOVO")${NC}"
            echo ""
            read -rp "Passar este replay agora? (s/N): " RESP

            JA_EXISTIA["$NOVO"]=1

            if [[ "$RESP" =~ ^[Ss]$ ]]; then
                passar_replay "$NOVO"
            else
                echo -e "${AMARELO}Ignorado. Continuando monitoramento...${NC}"
                sleep 1
            fi

            echo -e "${AZUL}🔄 Aguardando nova partida...${NC}"
        done < <(listar_replays)

        printf "\r⏱️  [%s] Monitorando... (Ctrl+C p/ sair)" "$(date '+%H:%M:%S')"
        sleep 2
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
        echo -e "  ${CIANO}1)${NC} 📡 Monitor automático (detecta pós-partida)"
        echo -e "  ${CIANO}2)${NC} 📋 Escolher replay manualmente"
        echo -e "  ${CIANO}3)${NC} ❌ Sair"
        echo ""
        read -rp "Opção: " OP
        case "$OP" in
            1) monitor_automatico  ;;
            2) menu_replays        ;;
            3) exit 0              ;;
            *) echo -e "${VERMELHO}Opção inválida${NC}"; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  INÍCIO
# ══════════════════════════════════════════════════
trap 'echo -e "\n${AMARELO}⚠️  Encerrado.${NC}"; exit 0' INT TERM

conectar_adb
login
menu_principal
