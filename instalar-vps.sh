#!/usr/bin/env bash
# Instala o Painel Completo DCG (full.dcgseguros.io) na VPS.
# Rode este script DENTRO da VPS, como root ou com sudo.
#
# O que ele faz:
#   1. Clona/atualiza o repositório crm-diretoria (branch da versão completa)
#   2. Copia o index.html para a pasta pública do site
#   3. Cria o bloco do Nginx para full.dcgseguros.io (se ainda não existir)
#   4. Recarrega o Nginx
#   5. Pede certificado HTTPS via certbot (se disponível)
#
# Pré-requisitos antes de rodar:
#   - DNS: um registro A (ou CNAME) para "full.dcgseguros.io" apontando pro IP desta VPS
#   - Nginx já instalado
#   - Opcional: certbot instalado, para gerar HTTPS automaticamente

set -euo pipefail

DOMINIO="full.dcgseguros.io"
REPO_URL="https://github.com/diniz2025/crm-diretoria.git"
BRANCH="claude/dcgseguros-vps-optimization-gtti50"
PASTA_CLONE="/opt/dcg-painel-completo"
PASTA_PUBLICA="/var/www/${DOMINIO}"
NGINX_CONF="/etc/nginx/sites-available/${DOMINIO}"

echo "==> Clonando/atualizando o repositório..."
if [ -d "$PASTA_CLONE/.git" ]; then
  git -C "$PASTA_CLONE" fetch origin "$BRANCH"
  git -C "$PASTA_CLONE" checkout "$BRANCH"
  git -C "$PASTA_CLONE" reset --hard "origin/$BRANCH"
else
  git clone --branch "$BRANCH" "$REPO_URL" "$PASTA_CLONE"
fi

echo "==> Publicando arquivos estáticos..."
mkdir -p "$PASTA_PUBLICA"
cp "$PASTA_CLONE/index.html" "$PASTA_PUBLICA/index.html"

echo "==> Configurando Nginx..."
if [ ! -f "$NGINX_CONF" ]; then
  cat > "$NGINX_CONF" <<EOF
server {
    listen 80;
    server_name ${DOMINIO};
    root ${PASTA_PUBLICA};
    index index.html;

    location / {
        try_files \$uri \$uri/ /index.html;
    }
}
EOF
  ln -sf "$NGINX_CONF" "/etc/nginx/sites-enabled/${DOMINIO}"
  echo "   Bloco do Nginx criado para ${DOMINIO}."
else
  echo "   Bloco do Nginx já existia, mantido como estava."
fi

echo "==> Testando e recarregando Nginx..."
nginx -t
systemctl reload nginx

echo "==> HTTPS (certbot)..."
if command -v certbot >/dev/null 2>&1; then
  certbot --nginx -d "$DOMINIO" --non-interactive --agree-tos -m diniz@dcgseguros.com.br || \
    echo "   Certbot falhou ou pediu interação manual — rode 'certbot --nginx -d ${DOMINIO}' na mão."
else
  echo "   Certbot não encontrado. Instale com 'apt install certbot python3-certbot-nginx' e rode:"
  echo "   certbot --nginx -d ${DOMINIO}"
fi

echo ""
echo "==> Pronto. Confira em: http://${DOMINIO} (ou https:// depois do certbot)"
