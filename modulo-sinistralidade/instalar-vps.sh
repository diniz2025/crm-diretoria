#!/usr/bin/env bash
# ============================================================
# MÓDULO SINISTRALIDADE DCG — instalador para a VPS
# Executar NA VPS (76.13.232.202), a partir da pasta deste módulo:
#
#   APP_DIR=/caminho/do/app/diseg DB_NAME=<banco> DB_USER=<usuario_pg> \
#     bash instalar-vps.sh
#
# Variáveis opcionais: PM2_ID (padrão 20) e APP_PORT (padrão 3070).
# Protocolo Verdade V2.0: backup antes, validação depois.
# ============================================================
set -euo pipefail

APP_DIR="${APP_DIR:?Defina APP_DIR=/caminho/do/app/diseg}"
DB_NAME="${DB_NAME:?Defina DB_NAME=<banco do diseg>}"
DB_USER="${DB_USER:?Defina DB_USER=<usuario postgres>}"
PM2_ID="${PM2_ID:-20}"
APP_PORT="${APP_PORT:-3070}"
MODULO_DIR="$(cd "$(dirname "$0")" && pwd)"
STAMP="$(date +%F_%H%M%S)"

echo "==> [0/6] Backup (Protocolo Verdade V2.0)"
pg_dump -U "$DB_USER" "$DB_NAME" > "$HOME/backup_pre_sinistralidade_${STAMP}.sql"
tar -czf "$HOME/backup_app_diseg_${STAMP}.tar.gz" -C "$(dirname "$APP_DIR")" "$(basename "$APP_DIR")" \
  --exclude node_modules --exclude uploads
echo "    Banco:  $HOME/backup_pre_sinistralidade_${STAMP}.sql"
echo "    App:    $HOME/backup_app_diseg_${STAMP}.tar.gz"

echo "==> [1/6] Migração do banco (reexecutável, não duplica seed)"
psql -U "$DB_USER" -d "$DB_NAME" -v ON_ERROR_STOP=1 -f "$MODULO_DIR/sql/001_sinistralidade.sql"

echo "==> [2/6] Copiando arquivos para o app"
mkdir -p "$APP_DIR/routes" "$APP_DIR/public/sinistralidade"
cp "$MODULO_DIR/routes/sinistralidade.js" "$APP_DIR/routes/"
cp "$MODULO_DIR/public/sinistralidade/index.html" "$APP_DIR/public/sinistralidade/"
cp "$MODULO_DIR/public/sinistralidade/cliente.html" "$APP_DIR/public/sinistralidade/"

echo "==> [3/6] Instalando dependência (multer)"
cd "$APP_DIR" && npm install multer --save

echo "==> [4/6] Verificando montagem das rotas no app principal"
MAIN_FILE=""
for f in app.js server.js index.js src/app.js src/server.js; do
  [ -f "$APP_DIR/$f" ] && MAIN_FILE="$APP_DIR/$f" && break
done
if [ -n "$MAIN_FILE" ] && grep -q "api/sinistralidade" "$MAIN_FILE"; then
  echo "    OK: rotas já montadas em $MAIN_FILE"
else
  echo "    ATENÇÃO: monte as rotas manualmente no arquivo principal (${MAIN_FILE:-app.js/server.js}):"
  echo "      app.use('/api/sinistralidade', authDCG, require('./routes/sinistralidade'));"
  echo "      // no authDCG, liberar req.path que começa com '/portal/'"
  echo "      app.use(express.static('public')); // se ainda não servir a pasta public"
  echo "    Confira também o require('../db') em routes/sinistralidade.js (pool PostgreSQL)."
  read -rp "    Pressione ENTER depois de montar as rotas para continuar... "
fi

echo "==> [5/6] Reiniciando PM2 (id $PM2_ID)"
pm2 restart "$PM2_ID"
sleep 3
pm2 logs "$PM2_ID" --lines 15 --nostream || true

echo "==> [6/6] Validação (não confiar, verificar)"
if curl -sf "http://localhost:${APP_PORT}/api/sinistralidade/contratos" | head -c 400; then
  echo
  echo "SUCESSO: módulo respondendo. Abra https://dcgseguros.io/sinistralidade/"
else
  echo "FALHOU: API não respondeu. Veja: pm2 logs $PM2_ID --lines 50"
  echo "Rollback do banco (se necessário): psql -U $DB_USER -d $DB_NAME < $HOME/backup_pre_sinistralidade_${STAMP}.sql"
  exit 1
fi
