# Módulo Sinistralidade DCG — Instalação no dcgseguros.io

Diferencial competitivo: acompanhamento mensal da sinistralidade dos contratos
100+ vidas (SLG/SulAmérica, Enob/Sistemas e Planos de Saúde) com painel para o
RH do cliente — sem surpresas na renovação.

## O que este módulo cobre (referências de mercado incorporadas)
- **Agger**: área exclusiva do cliente + alertas de status → portal via token
- **Quiver**: evidência documental do sinistro → guarda dos relatórios da operadora
- **Suridata (benchmark saúde)**: acumulado 12m, ofensores, alerta antes do reajuste → semáforo + projeção
- **SIAV/CronosSeg**: campo `cronosseg_id` já preparado para vincular apólices

## Melhorias desta versão (revisão de código)
- **Segurança/LGPD (crítico)**: o download do cliente agora é
  `GET /api/sinistralidade/portal/:token/arquivos/:id/download` — valida o token,
  o vínculo com o contrato e o flag `visivel_cliente`. Antes, qualquer pessoa com
  um ID sequencial baixava qualquer relatório (dado de saúde) sem login.
  A rota `/arquivos/:id/download` ficou só para o admin, atrás do login.
- **Bug corrigido**: o botão "excluir competência" não funcionava (a query não
  retornava o `id` do mês — o DELETE ia como `undefined`).
- O portal do cliente não expõe mais o CNPJ da empresa.
- Novas rotas: `PUT /contratos/:id` (editar vidas/break-even/VCMH) e
  `POST /contratos/:id/token` (revogar e regerar o link do RH).
- Painel admin ganhou formulário de novo contrato, edição de dados técnicos e
  botão de revogar link — sem precisar de curl/SQL manual.
- Validação de entradas (ids numéricos, competência AAAA-MM, prêmio > 0) —
  erros viram JSON 400 em vez de 500 do Postgres.
- Erros de upload (multer) respondem JSON em vez de HTML de stack trace.
- Escape de HTML nos painéis (nomes de empresa/arquivo não injetam markup).
- Migração SQL reexecutável de verdade: seed com `WHERE NOT EXISTS`
  (o `ON CONFLICT DO NOTHING` anterior duplicava o seed a cada execução,
  pois `empresa` não tem constraint UNIQUE) e `CREATE EXTENSION pgcrypto`
  incluído no próprio arquivo.

## Instalação rápida (VPS Principal 76.13.232.202, porta SSH 4422)

```bash
ssh -p 4422 usuario@76.13.232.202
git clone -b claude/dcgseguros-vps-optimization-gtti50 \
  https://github.com/diniz2025/crm-diretoria.git ~/modulo-sin-install
cd ~/modulo-sin-install/modulo-sinistralidade

APP_DIR=/caminho/do/app/diseg DB_NAME=<banco> DB_USER=<usuario_pg> \
  bash instalar-vps.sh
```

O script faz, nesta ordem: backup do banco e do app (Protocolo Verdade V2.0),
migração SQL, cópia dos arquivos, `npm install multer`, checagem da montagem
das rotas, `pm2 restart 20` e validação via curl na porta 3070.
`PM2_ID` e `APP_PORT` podem ser sobrescritos por variável de ambiente.

## Passo a passo manual (se preferir sem o script)

### 0. Backup ANTES de tudo (Protocolo Verdade V2.0)
```bash
pg_dump -U <usuario_pg> <banco_diseg> > ~/backup_pre_sinistralidade_$(date +%F).sql
cp -r /caminho/do/app/diseg ~/backup_app_diseg_$(date +%F)
```

### 1. Migração do banco
```bash
psql -U <usuario_pg> -d <banco_diseg> -f sql/001_sinistralidade.sql
```

### 2. Copiar arquivos para o app
```
routes/sinistralidade.js            -> <app>/routes/
public/sinistralidade/index.html    -> <app>/public/sinistralidade/
public/sinistralidade/cliente.html  -> <app>/public/sinistralidade/
```

### 3. Dependência e ajuste do pool
```bash
cd <app> && npm install multer --save
```
No `routes/sinistralidade.js`, ajuste a linha `const pool = require('../db')`
para o caminho real do pool PostgreSQL do Diseg.

### 4. Montar as rotas no app principal
No arquivo principal (app.js/server.js), adicione:
```js
app.use('/api/sinistralidade', authDCG, require('./routes/sinistralidade'));
// se ainda não servir a pasta public:
app.use(express.static('public'));
```
No middleware `authDCG`, libere APENAS o prefixo do portal do cliente:
```js
function authDCG(req, res, next) {
  if (req.path.startsWith('/portal/')) return next(); // RH via token
  // ... validação de sessão/login existente do Diseg ...
}
```
Tudo o mais (contratos, lançamentos, uploads, download admin) exige login.

### 5. Reiniciar (PM2 id 20, porta 3070)
```bash
pm2 restart 20 && pm2 logs 20 --lines 30
```

### 6. Validar (não confiar, verificar)
```bash
curl -s http://localhost:3070/api/sinistralidade/contratos | head
```
Deve retornar JSON com SLG e Enob (seed). Depois abra:
- Admin:  https://dcgseguros.io/sinistralidade/ (deve exigir login)
- Cliente: link exibido no cabeçalho de cada contrato (token único)

Teste de segurança obrigatório (numa aba anônima, sem login):
- `https://dcgseguros.io/api/sinistralidade/contratos` → deve NEGAR
- `https://dcgseguros.io/api/sinistralidade/arquivos/1/download` → deve NEGAR
- link do cliente com `?t=<token>` → deve ABRIR

### 7. Ajustar dados reais
No painel admin, lance as competências do relatório da operadora
(prêmio, sinistro, vidas). Vidas, break-even e VCMH reais de cada contrato
agora se editam direto no painel (seção "Dados técnicos do contrato").

## Segurança e LGPD
- Rota admin e API de escrita atrás do login do Diseg (ver passo 4).
- Portal do cliente: somente leitura, agregado, sem CNPJ, sem beneficiários.
- Download do cliente só entrega arquivo com `visivel_cliente = true` e do
  próprio contrato do token.
- Relatórios da operadora podem conter dado de saúde (dado sensível LGPD).
  Só marque "visível ao cliente" para versões agregadas.
- Link vazou? Botão "revogar e gerar novo link" no painel admin.

## Pendências conhecidas (não implementadas de propósito)
- Sync CronosSeg: endpoint `/sync/cronosseg` retorna 501 até termos as
  credenciais MySQL da Locaweb confirmadas.
- Leitura automática do PDF da operadora (OCR/parse): fase 2 — hoje o
  lançamento é manual, o que garante conferência humana antes de publicar
  ao cliente.
