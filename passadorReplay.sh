#!/bin/bash
# ╔══════════════════════════════════════════════════╗
# ║       PASSADOR DE REPLAY - FREE FIRE             ║
# ║       Modo: Automático (Monitor de Pasta)        ║
# ╚══════════════════════════════════════════════════╝
# Requer: adb, curl, bash (via Termux + android-tools)

set -u

# ──────────────────────────────────────────────────
#  CONFIGURAÇÕES — edite aqui antes de usar
# ──────────────────────────────────────────────────

# URL do seu Firebase Realtime Database
# Formato: https://SEU-PROJETO-default-rtdb.firebaseio.com
KEY_URL="https://passador-de-replay-default-rtdb.firebaseio.com"

# Pasta onde o usuário coloca os replays (.bin + .json)
# Os arquivos devem ir para a pasta Download do celular
REPLAY_SRC="/sdcard/Download"

# Pacote padrão ao iniciar (será trocado no menu)
PKG="com.dts.freefireth"
FF_SELECIONADO="Free Fire Normal"

# Destino dos replays dentro do Free Fire (calculado automaticamente)
DST_DIR="/sdcard/Android/data/${PKG}/files/MReplays"

# ──────────────────────────────────────────────────
#  VARIÁVEIS DE ESTADO (não mexa aqui)
# ──────────────────────────────────────────────────
CONN_PORT=""
USUARIO="N/A"
VALIDADE_USER="N/A"
ADB_STATUS="Desconectado"
APK_VER=""
declare -A PROCESSADOS=()  # Controla replays já processados no loop

# ──────────────────────────────────────────────────
#  CORES DO TERMINAL
# ──────────────────────────────────────────────────
NC='\033[0m'
VERDE='\033[1;32m'
VERMELHO='\033[1;31m'
AMARELO='\033[1;33m'
AZUL='\033[1;34m'
CIANO='\033[1;36m'

# ══════════════════════════════════════════════════
#  FUNÇÕES UTILITÁRIAS
# ══════════════════════════════════════════════════

# Mostra o cabeçalho com status atual na parte superior
header() {
    # Atualiza status do ADB antes de exibir
    if adb devices 2>/dev/null | grep -q "device$"; then
        ADB_STATUS="${VERDE}Conectado${NC}"
    else
        ADB_STATUS="${VERMELHO}Desconectado${NC}"
    fi

    clear
    echo -e "══════════════════════════════════════"
    echo -e " ${AZUL}USUÁRIO${NC}   : $USUARIO"
    echo -e " ${AMARELO}VALIDADE${NC}  : $VALIDADE_USER"
    echo -e " ${VERDE}FREE FIRE${NC} : $FF_SELECIONADO"
    echo -e " ${CIANO}ADB${NC}       : $(echo -e "$ADB_STATUS")"
    echo -e "══════════════════════════════════════"
    echo ""
}

# Pausa e aguarda o usuário pressionar Enter
pausar() {
    read -rp "Pressione Enter para continuar..."
}

# ══════════════════════════════════════════════════
#  PASSO 1 — CONECTAR ADB
# ══════════════════════════════════════════════════
# O ADB (Android Debug Bridge) permite que o script
# controle o celular via Wi-Fi usando o Termux.
#
# COMO FUNCIONA:
#   1. O usuário ativa "Depuração sem fio" no Android
#      (Configurações > Opções do desenvolvedor)
#   2. O Android mostra: porta de pareamento + código
#   3. O script pareia com 'adb pair' usando esses dados
#   4. Depois conecta com 'adb connect' na porta principal
# ══════════════════════════════════════════════════
conectar_adb() {
    clear
    echo "╔════════════════════════════════════╗"
    echo "║    PASSO 1: CONECTAR ADB           ║"
    echo "╚════════════════════════════════════╝"
    echo ""

    # Se já estiver conectado, não precisa reconectar
    if adb devices 2>/dev/null | grep -q "device$"; then
        echo -e "${VERDE}✅ ADB já está conectado!${NC}"
        sleep 1
        return
    fi

    echo -e "${AMARELO}Ative a Depuração sem fio no Android:${NC}"
    echo "   Configurações > Opções do desenvolvedor"
    echo "   > Depuração sem fio > Parear dispositivo"
    echo ""

    read -rp "Porta de pareamento (ex: 37821): " PAIR_PORT
    read -rp "Código de pareamento (ex: 123456): " PAIR_CODE

    # Pareia usando o código fornecido pelo Android
    printf '%s\n' "$PAIR_CODE" | adb pair "localhost:$PAIR_PORT" || {
        echo -e "${VERMELHO}❌ Falha no pareamento!${NC}"
        exit 1
    }

    echo ""
    read -rp "Porta de conexão principal (ex: 42345): " CONN_PORT

    # Conecta definitivamente ao dispositivo
    adb connect "localhost:$CONN_PORT" || {
        echo -e "${VERMELHO}❌ Falha ao conectar!${NC}"
        exit 1
    }

    if adb devices | grep -q "device$"; then
        echo -e "${VERDE}✅ ADB conectado com sucesso!${NC}"
    else
        echo -e "${VERMELHO}❌ Dispositivo não reconhecido${NC}"
        exit 1
    fi

    sleep 1
}

# ══════════════════════════════════════════════════
#  PASSO 2 — LOGIN POR CHAVE (LICENÇA)
# ══════════════════════════════════════════════════
# COMO FUNCIONA:
#   1. O usuário digita a KEY (código de licença)
#   2. O script lê o android_id do celular (UID único)
#   3. Consulta o Firebase: GET /KEY.json
#   4. O Firebase retorna: status, validade, cliente, uid
#   5. Se status=Ativo e validade não expirou → OK
#   6. Se ainda não tem UID salvo, vincula o celular
#   7. Se o UID não bate com o do Firebase → bloqueado
#
# Estrutura esperada no Firebase Realtime Database:
#   {
#     "SUACHAVE123": {
#       "status": "Ativo",         <- Ativo / Pausado / Banido
#       "validade": "2025-12-31",  <- Data de expiração
#       "cliente": "João Silva",   <- Nome do cliente
#       "uid": ""                  <- Preenchido automaticamente
#     }
#   }
# ══════════════════════════════════════════════════
login() {
    clear
    echo "╔════════════════════════════════════╗"
    echo "║    PASSO 2: LOGIN POR CHAVE        ║"
    echo "╚════════════════════════════════════╝"
    echo ""

    read -rp "Digite sua KEY de acesso: " USER_KEY

    # Lê o android_id — identificador único do dispositivo
    DEVICE_ID="$(adb shell settings get secure android_id 2>/dev/null | tr -d '\r')"
    [[ -z "$DEVICE_ID" || "$DEVICE_ID" == "null" ]] && {
        echo -e "${VERMELHO}❌ Erro ao obter UID do dispositivo${NC}"
        exit 1
    }

    echo -e "${AZUL}🔑 Verificando chave no servidor...${NC}"

    # Busca os dados da KEY no Firebase
    RESP="$(curl -s "$KEY_URL/$USER_KEY.json")"
    [[ -z "$RESP" || "$RESP" == "null" ]] && {
        echo -e "${VERMELHO}❌ KEY inválida ou não encontrada${NC}"
        exit 1
    }

    # Extrai os campos do JSON retornado
    STATUS="$(echo "$RESP"   | sed -n 's/.*"status":"\([^"]*\)".*/\1/p')"
    VALIDADE="$(echo "$RESP" | sed -n 's/.*"validade":"\([^"]*\)".*/\1/p')"
    CLIENTE="$(echo "$RESP"  | sed -n 's/.*"cliente":"\([^"]*\)".*/\1/p')"
    UID_SERVER="$(echo "$RESP" | sed -n 's/.*"uid":"\([^"]*\)".*/\1/p')"

    # Verifica o status da key
    case "$STATUS" in
        Ativo)   ;;  # Continua normalmente
        Pausado) echo -e "${VERMELHO}❌ KEY pausada${NC}"; exit 1 ;;
        Banido)  echo -e "${VERMELHO}❌ KEY banida${NC}";  exit 1 ;;
        *)       echo -e "${VERMELHO}❌ Status inválido: $STATUS${NC}"; exit 1 ;;
    esac

    # Verifica se a KEY ainda está dentro da validade
    VALIDADE_TS="$(date -d "$VALIDADE 23:59:59" +%s 2>/dev/null)"
    DEVICE_TS="$(adb shell date +%s 2>/dev/null | tr -d '\r')"

    [[ -z "$VALIDADE_TS" ]] && {
        echo -e "${VERMELHO}❌ Data de validade inválida: $VALIDADE${NC}"
        exit 1
    }

    (( DEVICE_TS > VALIDADE_TS )) && {
        echo -e "${VERMELHO}❌ KEY expirada em $VALIDADE${NC}"
        exit 1
    }

    # Vincula o UID ao servidor se for o primeiro uso
    if [[ -z "$UID_SERVER" ]]; then
        curl -s -X PATCH \
            -H "Content-Type: application/json" \
            -d "{\"uid\":\"$DEVICE_ID\"}" \
            "$KEY_URL/$USER_KEY.json" >/dev/null
        echo -e "${VERDE}✅ Dispositivo vinculado com sucesso!${NC}"

    # Bloqueia se o UID não bate (outro celular tentando usar a mesma key)
    elif [[ "$UID_SERVER" != "$DEVICE_ID" ]]; then
        echo -e "${VERMELHO}❌ KEY já vinculada a outro dispositivo${NC}"
        exit 1
    fi

    # Salva os dados para exibir no cabeçalho
    USUARIO="$CLIENTE"
    VALIDADE_USER="$VALIDADE"

    echo ""
    echo -e "${VERDE}✅ Login realizado!${NC}"
    echo -e "👤 Usuário : $USUARIO"
    echo -e "📅 Validade: $VALIDADE"
    sleep 2
}

# ══════════════════════════════════════════════════
#  PASSO 3 — SELECIONAR VERSÃO DO FREE FIRE
# ══════════════════════════════════════════════════
# Cada versão tem um pacote (PKG) diferente no Android.
# Isso define também onde os replays serão copiados.
# ══════════════════════════════════════════════════
selecionar_ff() {
    header
    echo "Escolha a versão do Free Fire instalada:"
    echo ""
    echo "  1) Free Fire Normal"
    echo "  2) Free Fire MAX"
    echo ""
    read -rp "Opção (1/2): " OP

    case "$OP" in
        1)
            PKG="com.dts.freefireth"
            FF_SELECIONADO="Free Fire Normal"
            ;;
        2)
            PKG="com.dts.freefiremax"
            FF_SELECIONADO="Free Fire MAX"
            ;;
        *)
            echo -e "${VERMELHO}Opção inválida${NC}"
            pausar
            return
            ;;
    esac

    # Atualiza o destino baseado na versão escolhida
    DST_DIR="/sdcard/Android/data/${PKG}/files/MReplays"

    # Lê a versão do APK instalado (necessária para corrigir o JSON)
    APK_VER="$(adb shell dumpsys package "$PKG" 2>/dev/null \
        | grep versionName | head -1 | sed 's/.*=//' | tr -d '\r')"

    echo ""
    echo -e "${VERDE}✅ Selecionado: $FF_SELECIONADO${NC}"
    echo -e "${VERDE}✅ Versão APK : ${APK_VER:-Desconhecida}${NC}"
    sleep 2
}

# ══════════════════════════════════════════════════
#  FUNÇÃO: PROCESSAR UM REPLAY (modo automático)
# ══════════════════════════════════════════════════
# COMO FUNCIONA:
#   1. Recebe o caminho do arquivo .bin detectado
#   2. Extrai o timestamp do nome do arquivo
#      Ex: replay_2024-01-15-22-30-45.bin → 2024-01-15-22-30-45
#   3. Corrige a versão do jogo no arquivo .json
#   4. Desativa a hora automática no Android
#   5. Abre as configurações de data/hora
#   6. Aguarda o usuário ajustar a data/hora manualmente
#   7. Fica em loop monitorando até bater o segundo exato
#   8. No segundo exato: copia .bin e .json para a pasta do FF
#   9. Restaura a hora automática
#  10. Remove os originais da pasta Download
# ══════════════════════════════════════════════════
processar_replay() {
    local BIN="$1"
    local JSON="${BIN%.bin}.json"

    clear
    echo "╔════════════════════════════════════╗"
    echo "║    ⚡ REPLAY DETECTADO!             ║"
    echo "╚════════════════════════════════════╝"
    echo ""
    echo -e "${VERDE}Arquivo: $(basename "$BIN")${NC}"

    # Verifica se o .json correspondente existe
    if ! adb shell "[ -f \"$JSON\" ]" 2>/dev/null; then
        echo -e "${VERMELHO}❌ JSON não encontrado para este replay${NC}"
        sleep 3
        return 1
    fi

    # Extrai o timestamp do nome do arquivo
    # Padrão esperado: qualquer-coisa_YYYY-MM-DD-HH-MM-SS.bin
    local TS
    TS=$(basename "$BIN" | grep -oE '[0-9]{4}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}-[0-9]{2}')

    if [[ -z "$TS" ]]; then
        echo -e "${VERMELHO}❌ Timestamp inválido no nome do arquivo${NC}"
        echo    "   Nome esperado: replay_YYYY-MM-DD-HH-MM-SS.bin"
        sleep 3
        return 1
    fi

    echo ""
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo -e "${CIANO}📅 DATA: ${AMARELO}${TS:0:10}${NC}"
    echo -e "${CIANO}⏰ HORA: ${AMARELO}${TS:11:2}:${TS:14:2}:${TS:17:2}${NC}"
    echo -e "${AZUL}══════════════════════════════════════${NC}"
    echo ""

    # Atualiza a versão do APK e corrige no JSON
    # (sem a versão correta, o Free Fire rejeita o replay)
    APK_VER="$(adb shell dumpsys package "$PKG" 2>/dev/null \
        | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')"

    if [[ -n "$APK_VER" ]]; then
        adb shell \
            "sed -i 's/\"Version\":\"[^\"]*\"/\"Version\":\"$APK_VER\"/g' \"$JSON\"" \
            >/dev/null 2>&1
        echo -e "${VERDE}✅ Versão corrigida no JSON: $APK_VER${NC}"
    fi

    # Desativa a sincronização automática de data/hora
    adb shell "settings put global auto_time 0"      >/dev/null 2>&1
    adb shell "settings put global auto_time_zone 0" >/dev/null 2>&1

    # Abre as configurações de data e hora no celular
    adb shell "am start -a android.settings.DATE_SETTINGS" >/dev/null 2>&1

    echo ""
    echo -e "${AMARELO}📲 AJUSTE A DATA E HORA NO CELULAR PARA:${NC}"
    echo -e "   ${VERDE}Data : ${TS:0:4}-${TS:5:2}-${TS:8:2}${NC}"
    echo -e "   ${VERDE}Hora : ${TS:11:2}:${TS:14:2}:${TS:17:2}${NC}"
    echo ""
    echo -e "${CIANO}⏳ Aguardando ajuste... (monitorando em 3s)${NC}"
    sleep 3

    # Loop: fica verificando a hora do celular até bater o timestamp exato
    echo -e "${AZUL}🔄 Aguardando o segundo exato: $TS${NC}"
    while true; do
        NOW=$(adb shell date '+%Y-%m-%d-%H-%M-%S' 2>/dev/null | tr -d '\r')
        printf "\r⏰ Hora atual no celular: %s" "$NOW"

        if [[ "$NOW" == "$TS" ]]; then
            echo -e "\n${VERDE}✅ SEGUNDO EXATO ATINGIDO!${NC}"
            break
        fi
        sleep 0.2
    done

    # Volta para a tela inicial do celular
    adb shell "input keyevent KEYCODE_BACK" >/dev/null 2>&1
    adb shell "input keyevent KEYCODE_HOME" >/dev/null 2>&1

    # Garante que a pasta de destino existe
    adb shell "mkdir -p \"$DST_DIR\"" >/dev/null 2>&1

    local BIN_DST="$DST_DIR/$(basename "$BIN")"
    local JSON_DST="$DST_DIR/$(basename "$JSON")"

    echo "📁 Copiando arquivos para o Free Fire..."

    # Copia o .bin: lê do celular via exec-out e escreve na pasta do FF
    adb exec-out "cat \"$BIN\""  | adb shell "cat > \"$BIN_DST\""  2>/dev/null
    adb exec-out "cat \"$JSON\"" | adb shell "cat > \"$JSON_DST\"" 2>/dev/null

    # Restaura a hora automática
    adb shell "settings put global auto_time 1"      >/dev/null 2>&1
    adb shell "settings put global auto_time_zone 1" >/dev/null 2>&1

    # Remove os originais da pasta Download (limpeza)
    adb shell "rm -f \"$BIN\" \"$JSON\"" >/dev/null 2>&1

    echo -e "${VERDE}✅ REPLAY PASSADO COM SUCESSO!${NC}"
    echo ""
    echo -e "${CIANO}Voltando ao monitoramento em 3 segundos...${NC}"
    sleep 3
}

# ══════════════════════════════════════════════════
#  LOOP AUTOMÁTICO — Monitor de pasta
# ══════════════════════════════════════════════════
# COMO FUNCIONA:
#   - Fica verificando a pasta $REPLAY_SRC a cada 2s
#   - Quando encontra um .bin com .json correspondente,
#     chama processar_replay() automaticamente
#   - Registra os arquivos já processados em um array
#     para não processar o mesmo replay duas vezes
#   - Se o ADB desconectar, tenta reconectar sozinho
# ══════════════════════════════════════════════════
loop_automatico() {
    header
    echo "╔════════════════════════════════════╗"
    echo "║    📡 MONITORAMENTO AUTOMÁTICO     ║"
    echo "╚════════════════════════════════════╝"
    echo ""
    echo -e "${VERDE}📁 Monitorando  : $REPLAY_SRC${NC}"
    echo -e "${VERDE}🎯 Destino      : $DST_DIR${NC}"
    echo ""
    echo -e "${CIANO}⏳ Verificando a cada 2 segundos...${NC}"
    echo -e "${AMARELO}⚠️  Para parar: Ctrl+C${NC}"
    echo ""
    sleep 2

    while true; do

        # Verifica se o ADB ainda está conectado
        if ! adb devices 2>/dev/null | grep -q "device$"; then
            clear
            echo -e "${VERMELHO}❌ ADB desconectado!${NC}"
            echo -e "${AMARELO}🔄 Tentando reconectar em localhost:$CONN_PORT...${NC}"
            adb connect "localhost:$CONN_PORT" 2>/dev/null
            sleep 3
            continue
        fi

        # Lista todos os .bin que tenham um .json correspondente na pasta
        mapfile -t BINS < <(
            adb shell "
                for f in \"$REPLAY_SRC\"/*.bin; do
                    [ -f \"\$f\" ] || continue
                    j=\"\${f%.bin}.json\"
                    [ -f \"\$j\" ] && echo \"\$f\"
                done
            " 2>/dev/null | tr -d '\r'
        )

        if [[ ${#BINS[@]} -gt 0 ]]; then
            for BIN in "${BINS[@]}"; do
                # Pula se já foi processado nesta sessão
                [[ -z "$BIN" ]]                      && continue
                [[ -n "${PROCESSADOS[$BIN]:-}" ]]    && continue

                # Marca como processado e chama o processador
                PROCESSADOS["$BIN"]="1"
                processar_replay "$BIN"
            done
        else
            # Nenhum replay encontrado — exibe status de espera
            printf "\r${AMARELO}[%s] Aguardando novos replays... (Ctrl+C p/ sair)${NC}" \
                "$(date '+%H:%M:%S')"
            sleep 2
        fi

    done
}

# ══════════════════════════════════════════════════
#  FUNÇÃO: PASSAR REPLAY MANUALMENTE (modo menu)
# ══════════════════════════════════════════════════
passar_replay_manual() {
    header

    # Atualiza a versão do APK
    APK_VER="$(adb shell dumpsys package "$PKG" 2>/dev/null \
        | grep -m1 versionName | sed 's/.*=//' | tr -d '\r')"

    if [[ -z "$APK_VER" ]]; then
        echo -e "${VERMELHO}❌ Erro ao obter versão do APK${NC}"
        pausar
        return
    fi

    # Lista replays disponíveis com .json correspondente
    mapfile -t BINS < <(
        adb shell "
            for f in \"$REPLAY_SRC\"/*.bin; do
                [ -f \"\$f\" ] || continue
                j=\"\${f%.bin}.json\"
                [ -f \"\$j\" ] && echo \"\$f\"
            done
        " 2>/dev/null | tr -d '\r'
    )

    if [[ ${#BINS[@]} -eq 0 ]]; then
        echo -e "${VERMELHO}Nenhum replay válido encontrado em $REPLAY_SRC${NC}"
        echo    "Coloque o .bin e o .json na pasta Download do celular."
        pausar
        return
    fi

    echo "Replays disponíveis:"
    echo ""
    for i in "${!BINS[@]}"; do
        printf "  %2d) %s\n" $((i+1)) "$(basename "${BINS[$i]}")"
    done
    echo ""

    read -rp "Número do replay a passar: " sel

    if ! [[ "$sel" =~ ^[0-9]+$ ]] || (( sel < 1 || sel > ${#BINS[@]} )); then
        echo -e "${VERMELHO}Opção inválida${NC}"
        pausar
        return
    fi

    processar_replay "${BINS[$((sel-1))]}"
    pausar
}

# ══════════════════════════════════════════════════
#  MENU PRINCIPAL
# ══════════════════════════════════════════════════
menu_principal() {
    while true; do
        header
        echo "  MENU PRINCIPAL"
        echo ""
        echo "  1) Selecionar versão do Free Fire"
        echo "  2) Monitoramento automático (recomendado)"
        echo "  3) Passar replay manualmente"
        echo "  4) Sair"
        echo ""
        read -rp "Opção: " OP

        case "$OP" in
            1) selecionar_ff       ;;
            2) loop_automatico     ;;
            3) passar_replay_manual ;;
            4) exit 0              ;;
            *) echo -e "${VERMELHO}Opção inválida${NC}"; sleep 1 ;;
        esac
    done
}

# ══════════════════════════════════════════════════
#  EXECUÇÃO PRINCIPAL
# ══════════════════════════════════════════════════

# Captura Ctrl+C para sair com mensagem limpa
trap 'echo -e "\n${AMARELO}⚠️  Script encerrado pelo usuário${NC}"; exit 0' INT TERM

# Sequência de inicialização
conectar_adb   # 1. Conecta o ADB via Wi-Fi
login          # 2. Verifica a licença no Firebase
selecionar_ff  # 3. Escolhe a versão do Free Fire
menu_principal # 4. Exibe o menu
