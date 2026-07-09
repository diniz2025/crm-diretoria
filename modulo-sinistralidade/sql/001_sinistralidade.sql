-- ============================================================
-- MÓDULO SINISTRALIDADE DCG — Migração 001
-- Banco: PostgreSQL (mesmo banco do dcgseguros.io)
-- PROTOCOLO VERDADE: faça backup antes de executar
--   pg_dump -U <usuario> <banco> > backup_pre_sinistralidade.sql
-- Reexecutável: pode rodar mais de uma vez sem duplicar nada.
-- ============================================================

CREATE EXTENSION IF NOT EXISTS pgcrypto;  -- gen_random_bytes p/ tokens

BEGIN;

-- Contratos de saúde acompanhados (100+ vidas, fora do pool)
CREATE TABLE IF NOT EXISTS sin_contratos (
  id            SERIAL PRIMARY KEY,
  empresa       VARCHAR(160) NOT NULL,           -- ex: SLG Comércio de Sistemas
  cnpj          VARCHAR(18),
  operadora     VARCHAR(120) NOT NULL,           -- ex: SulAmérica
  produto       VARCHAR(160),                    -- ex: Especial 100
  vidas         INTEGER NOT NULL DEFAULT 0,
  break_even    NUMERIC(5,2) NOT NULL DEFAULT 70.00,  -- % contratual
  mes_reajuste  INTEGER CHECK (mes_reajuste BETWEEN 1 AND 12),
  vcmh_estimada NUMERIC(5,2) DEFAULT 12.00,      -- inflação médica p/ projeção
  cronosseg_id  VARCHAR(40),                     -- vínculo futuro CronosSeg
  token_cliente VARCHAR(64) UNIQUE,              -- acesso portal do RH
  ativo         BOOLEAN NOT NULL DEFAULT TRUE,
  criado_em     TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

-- Lançamentos mensais (prêmio x sinistro) extraídos do relatório da operadora
CREATE TABLE IF NOT EXISTS sin_meses (
  id           SERIAL PRIMARY KEY,
  contrato_id  INTEGER NOT NULL REFERENCES sin_contratos(id) ON DELETE CASCADE,
  competencia  DATE NOT NULL,                    -- sempre dia 01 do mês
  premio       NUMERIC(14,2) NOT NULL CHECK (premio > 0),
  sinistro     NUMERIC(14,2) NOT NULL CHECK (sinistro >= 0),
  vidas_mes    INTEGER,
  observacao   TEXT,
  criado_em    TIMESTAMPTZ NOT NULL DEFAULT NOW(),
  UNIQUE (contrato_id, competencia)
);

-- Relatórios originais da operadora (PDF/Excel) — guarda de evidência
CREATE TABLE IF NOT EXISTS sin_arquivos (
  id           SERIAL PRIMARY KEY,
  contrato_id  INTEGER NOT NULL REFERENCES sin_contratos(id) ON DELETE CASCADE,
  competencia  DATE,
  nome_arquivo VARCHAR(255) NOT NULL,
  caminho      VARCHAR(500) NOT NULL,            -- /var/www/diseg/uploads/sinistralidade/...
  mime         VARCHAR(120),
  tamanho      INTEGER,
  visivel_cliente BOOLEAN NOT NULL DEFAULT FALSE, -- LGPD: só expor ao RH se autorizado
  enviado_em   TIMESTAMPTZ NOT NULL DEFAULT NOW()
);

CREATE INDEX IF NOT EXISTS idx_sin_meses_contrato ON sin_meses (contrato_id, competencia DESC);
CREATE INDEX IF NOT EXISTS idx_sin_arquivos_contrato ON sin_arquivos (contrato_id);

-- Seed inicial: contratos citados pelo Diniz (ajustar vidas/break-even reais).
-- WHERE NOT EXISTS em vez de ON CONFLICT: empresa não tem constraint UNIQUE,
-- então ON CONFLICT DO NOTHING duplicaria o seed a cada reexecução.
INSERT INTO sin_contratos (empresa, operadora, produto, vidas, break_even, token_cliente)
SELECT 'SLG Comércio de Sistemas', 'SulAmérica', 'Especial 100', 0, 70.00, encode(gen_random_bytes(24), 'hex')
WHERE NOT EXISTS (SELECT 1 FROM sin_contratos WHERE empresa = 'SLG Comércio de Sistemas');

INSERT INTO sin_contratos (empresa, operadora, produto, vidas, break_even, token_cliente)
SELECT 'Enob', 'Sistemas e Planos de Saúde', NULL, 0, 70.00, encode(gen_random_bytes(24), 'hex')
WHERE NOT EXISTS (SELECT 1 FROM sin_contratos WHERE empresa = 'Enob');

COMMIT;
