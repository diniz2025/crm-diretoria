-- Painel Completo DCG (full.dcgseguros.io) — uso interno, exclusivo do Diniz.
-- Banco: projeto Supabase "dcg-client-data-enrich" (org dcg-hub).
-- Rode este arquivo inteiro no SQL Editor do Supabase antes de publicar o app.

-- ==========================================================================
-- CRM — carteira de contratos (mesmo modelo do crm-diretoria original)
-- ==========================================================================
create table if not exists contratos (
  id bigint generated always as identity primary key,
  cliente text not null default 'S/N',
  cnpj text default '',
  email text default '',
  telefone text default '',
  cep text default '',
  logradouro text default '',
  bairro text default '',
  cidade text default '',
  uf text default '',
  operadora text default '—',
  vidas integer default 0,
  premio numeric(12,2) default 0,
  comissao numeric(5,2) default 0,
  agenciamento numeric(5,2) default 0,
  estagio text default 'Implantado',
  status_manual text default 'auto',
  data_pagamento date,
  data_renovacao date default '2026-01-01',
  feedback text default '',
  consultor text default 'Diniz',
  criado_em timestamptz default now()
);

-- ==========================================================================
-- Prospecção — empresas-alvo (Receita Federal / busca manual)
-- ==========================================================================
create table if not exists empresas (
  id bigint generated always as identity primary key,
  cnpj text unique,
  razao_social text,
  nome_fantasia text,
  segmento text,
  cnae_descricao text,
  cidade text,
  uf text,
  situacao_cadastral text default 'A CONSULTAR',
  origem text default 'manual',
  status_enriquecimento text default 'Não Encontrado',
  observacoes text,
  criado_em timestamptz default now()
);

-- ==========================================================================
-- Decisores — sócios/RH/financeiro encontrados por empresa (skill de enriquecimento)
-- ==========================================================================
create table if not exists decisores (
  id bigint generated always as identity primary key,
  empresa_id bigint references empresas(id) on delete cascade,
  nome text not null,
  cargo text,
  prioridade text default '🥉 3',
  email text,
  email_status text default 'Não Validado',
  whatsapp text,
  telefone text,
  linkedin_url text,
  instagram_url text,
  fonte text,
  criado_em timestamptz default now()
);

-- ==========================================================================
-- Campanhas e envios
-- ==========================================================================
create table if not exists campanhas (
  id bigint generated always as identity primary key,
  nome text not null,
  canal text default 'email' check (canal in ('email','whatsapp')),
  assunto text,
  corpo text,
  status text default 'Rascunho' check (status in ('Rascunho','Ativa','Pausada','Concluída')),
  criado_em timestamptz default now()
);

create table if not exists envios_campanha (
  id bigint generated always as identity primary key,
  campanha_id bigint references campanhas(id) on delete cascade,
  decisor_id bigint references decisores(id) on delete set null,
  status text default 'Fila' check (status in ('Fila','Enviado','Aberto','Respondido','Erro')),
  enviado_em timestamptz
);

-- ==========================================================================
-- Pesquisas de satisfação (NPS/CSAT) com a carteira atual
-- ==========================================================================
create table if not exists pesquisas (
  id bigint generated always as identity primary key,
  titulo text not null,
  tipo text default 'NPS' check (tipo in ('NPS','CSAT')),
  pergunta text,
  ativa boolean default true,
  criado_em timestamptz default now()
);

create table if not exists respostas_pesquisa (
  id bigint generated always as identity primary key,
  pesquisa_id bigint references pesquisas(id) on delete cascade,
  contrato_id bigint references contratos(id) on delete set null,
  cliente_nome text,
  nota integer check (nota between 0 and 10),
  comentario text,
  criado_em timestamptz default now()
);

-- ==========================================================================
-- Hub "Geral" — atalhos para os outros sites/projetos do Diniz
-- ==========================================================================
create table if not exists links_hub (
  id bigint generated always as identity primary key,
  titulo text not null,
  url text not null,
  categoria text default 'Projetos',
  icone text default '🔗',
  ordem integer default 0
);

insert into links_hub (titulo, url, categoria, icone, ordem) values
  ('DCG Seguros — Site Principal', 'https://www.dcgseguros.com.br', 'Sites', '🌐', 1),
  ('DCG Seguros — SaaS (landing)', 'https://dcgseguros.io', 'Sites', '🚀', 2),
  ('DCG Seguros — Página Diniz', 'https://diniz.dcgseguros.io', 'Sites', '👤', 3),
  ('Gmail', 'https://mail.google.com', 'Google', '📧', 4),
  ('Google Drive', 'https://drive.google.com', 'Google', '📁', 5),
  ('Google Calendar', 'https://calendar.google.com', 'Google', '📅', 6),
  ('GitHub — Repositórios DCG', 'https://github.com/diniz2025?tab=repositories', 'Dev', '🐙', 7)
on conflict do nothing;

-- ==========================================================================
-- Segurança: RLS — só usuário autenticado (você) acessa
-- ==========================================================================
alter table contratos enable row level security;
alter table empresas enable row level security;
alter table decisores enable row level security;
alter table campanhas enable row level security;
alter table envios_campanha enable row level security;
alter table pesquisas enable row level security;
alter table respostas_pesquisa enable row level security;
alter table links_hub enable row level security;

do $$
declare t text;
begin
  for t in select unnest(array['contratos','empresas','decisores','campanhas','envios_campanha','pesquisas','respostas_pesquisa','links_hub'])
  loop
    execute format('drop policy if exists "auth_full_access" on %I', t);
    execute format('create policy "auth_full_access" on %I for all using (auth.uid() is not null) with check (auth.uid() is not null)', t);
  end loop;
end $$;
