# crm-diretoria — Dental M.I

Aplicação web (single-file, `index.html`) de gestão comercial e operacional da DCG Seguros para clínicas odontológicas: funil de vendas, carteira de clientes, financeiro e auditoria. Usa Supabase para dados/autenticação, Chart.js para gráficos e jsPDF para exportação de relatórios — tudo via CDN, sem build step.

## Estrutura

- `index.html` — aplicação completa (markup, estilos e lógica).
- `logo-dental.png` — logo usada na sidebar e no compartilhamento social.

## Desenvolvimento assistido por IA com 9Router (opcional)

Este projeto costuma ser desenvolvido com ferramentas de codificação por IA (Claude Code, Codex, Cursor etc.). Para reduzir custo de tokens e evitar bloqueios por limite de uso, é possível rotear essas ferramentas através do [9Router](https://9router.com/) ([repositório oficial](https://github.com/decolua/9router)) — um gateway local, compatível com a API da OpenAI, que distribui as chamadas entre múltiplos provedores com fallback automático.

O 9Router roda **na máquina de quem está desenvolvendo**, fora do escopo deste repositório — não é uma dependência do app.

### Instalação

Requer Node.js >= 18.

```bash
npm install -g 9router
```

Isso sobe um painel local em `http://localhost:20128` e expõe uma API compatível com OpenAI em `http://localhost:20128/v1`.

### Configuração de provedores

Crie um `.9router.yaml` (fora deste repositório, na sua máquina) listando os provedores disponíveis, por exemplo:

```yaml
providers:
  - name: anthropic
    type: claude
    api_key: ${ANTHROPIC_API_KEY}
    priority: 1
  - name: openai
    type: gpt
    api_key: ${OPENAI_API_KEY}
    priority: 2
```

Depois, aponte sua ferramenta de codificação (Claude Code, Codex, Cursor, etc.) para `http://localhost:20128/v1` como endpoint da API.

Consulte a [documentação oficial](https://github.com/decolua/9router) para a lista completa de provedores suportados e opções avançadas (RTK/compressão de tokens, tiers de fallback, etc.).
