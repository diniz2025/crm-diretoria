# DCG — Painel Completo (uso interno)

Versão completa/interna do CRM DCG, separada do SaaS público vendido a corretores.
Feita para rodar em `full.dcgseguros.io`, com login exclusivo do Diniz.

## O que já funciona
- Login via Supabase Auth (e-mail + senha)
- CRM: carteira de contratos, busca (cliente/operadora/vendedor), novo contrato
- Prospecção: busca de empresa por CNPJ na Receita Federal (BrasilAPI), salva como empresa-alvo
- Decisores: cadastro manual de sócios/RH/financeiro por empresa; fila de "pedir enriquecimento"
- Campanhas: criação de campanha (rascunho) — envio automático ainda não conectado
- Pesquisas: criação de pesquisa NPS/CSAT e cálculo de nota média das respostas
- Geral: hub de atalhos para outros sites/ferramentas (Gmail, Drive, Calendar, GitHub, sites DCG)

## Antes de publicar — 3 passos obrigatórios

1. **Rodar o schema no banco.** Abra o SQL Editor do projeto Supabase `dcg-client-data-enrich`
   (org `dcg-hub`) e execute o conteúdo de `schema.sql` inteiro.

2. **Criar seu usuário de login.** No mesmo projeto Supabase, vá em
   `Authentication > Users > Add user` e crie seu e-mail/senha. Esse será o único login do painel.

3. **Colar a chave da API.** Em `Settings > API` do projeto, copie a chave `anon` / `public`
   e cole em `index.html`, na linha:
   ```js
   const SUPABASE_KEY = 'COLE_AQUI_A_ANON_KEY_DO_PROJETO';
   ```

## Hospedagem
Arquivo único estático (sem build) — mesmo padrão do CRM anterior. Pode ser servido por
qualquer Nginx/static host apontando para esta pasta. Falta configurar o registro DNS de
`full.dcgseguros.io` apontando para o servidor onde os arquivos forem publicados.

## Pendências conhecidas (próximas etapas)
- **Campanhas**: falta conectar uma chave da Resend (e-mail) ou API de WhatsApp para o disparo real.
- **Decisores**: o enriquecimento automático (LinkedIn/Instagram/site) é feito pelo Claude a
  pedido — marque a empresa como "Em Fila" na tela de Prospecção e peça para processar a fila
  nesta conversa.
- **Google (Gmail/Drive/Calendar)**: os links do hub "Geral" hoje apenas abrem os apps do
  Google em outra aba. Para trazer os dados *dentro* do painel (ex: últimos e-mails, próximos
  eventos) é preciso criar credenciais OAuth no Google Cloud Console — isso requer acesso à
  sua conta Google e não pode ser feito remotamente por mim.
