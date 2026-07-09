/**
 * MÓDULO SINISTRALIDADE DCG — rotas Express
 * Montar no app principal do dcgseguros.io:
 *   const sinistralidade = require('./routes/sinistralidade');
 *   app.use('/api/sinistralidade', authDCG, sinistralidade);
 *
 * IMPORTANTE (segurança): as rotas que começam com /portal/ são as ÚNICAS
 * que o cliente (RH) acessa sem login — elas validam o token do contrato.
 * Se o seu middleware de auth for aplicado no mount inteiro, libere apenas
 * o prefixo /api/sinistralidade/portal/ (ex.: no authDCG, next() quando
 * req.path começar com '/portal/').
 *
 * Requer: npm install multer --save
 * Reutiliza o pool PostgreSQL do app (ajuste o require abaixo se o caminho for outro).
 */
const express = require('express');
const multer = require('multer');
const path = require('path');
const fs = require('fs');
const crypto = require('crypto');
const router = express.Router();

// >>> AJUSTE AQUI: aponte para o pool já existente do Diseg <<<
const pool = require('../db'); // ex.: module.exports = new Pool({...})

// Upload de relatórios da operadora
const UPLOAD_DIR = process.env.SIN_UPLOAD_DIR || path.join(__dirname, '..', 'uploads', 'sinistralidade');
fs.mkdirSync(UPLOAD_DIR, { recursive: true });
const upload = multer({
  storage: multer.diskStorage({
    destination: (_req, _file, cb) => cb(null, UPLOAD_DIR),
    filename: (_req, file, cb) => {
      const safe = file.originalname.replace(/[^a-zA-Z0-9._-]/g, '_');
      cb(null, `${Date.now()}_${safe}`);
    }
  }),
  limits: { fileSize: 20 * 1024 * 1024 }, // 20 MB
  fileFilter: (_req, file, cb) => {
    const ok = /pdf|excel|spreadsheet|csv/.test(file.mimetype) || /\.(pdf|xlsx?|csv)$/i.test(file.originalname);
    cb(ok ? null : new Error('Formato não permitido (PDF, Excel ou CSV)'), ok);
  }
});

// Validações básicas — evitam 500 do Postgres virar resposta crua
const idValido = (v) => /^\d+$/.test(String(v));
const normalizarCompetencia = (c) =>
  (typeof c === 'string' && /^\d{4}-(0[1-9]|1[0-2])/.test(c)) ? c.slice(0, 7) + '-01' : null;

// ------------------------------------------------------------------
// Cálculo central: série mensal + acumulado 12m + status + projeção
// ------------------------------------------------------------------
async function calcularContrato(contratoId) {
  const { rows: [contrato] } = await pool.query('SELECT * FROM sin_contratos WHERE id=$1', [contratoId]);
  if (!contrato) return null;

  const { rows: meses } = await pool.query(
    `SELECT id, competencia, premio, sinistro, vidas_mes,
            ROUND(sinistro/premio*100, 2) AS indice
       FROM sin_meses WHERE contrato_id=$1 ORDER BY competencia`, [contratoId]);

  // Acumulado móvel 12 meses (critério usado pelas operadoras no reajuste)
  const serie = meses.map((m, i) => {
    const janela = meses.slice(Math.max(0, i - 11), i + 1);
    const p = janela.reduce((s, x) => s + Number(x.premio), 0);
    const s = janela.reduce((s2, x) => s2 + Number(x.sinistro), 0);
    return { ...m, acumulado12m: p > 0 ? Number((s / p * 100).toFixed(2)) : null };
  });

  const ultimo = serie[serie.length - 1] || null;
  const be = Number(contrato.break_even);
  let status = 'sem_dados';
  if (ultimo && ultimo.acumulado12m != null) {
    const acc = ultimo.acumulado12m;
    status = acc < be - 5 ? 'saudavel' : acc <= be ? 'atencao' : 'critico';
  }

  // Projeção simples de reajuste: excedente sobre break-even + VCMH
  let projecao = null;
  if (ultimo && ultimo.acumulado12m != null) {
    const excedente = Math.max(0, ultimo.acumulado12m - be);
    projecao = Number((excedente + Number(contrato.vcmh_estimada || 0)).toFixed(2));
  }

  return { contrato, serie, ultimo, status, projecao_reajuste: projecao };
}

// ------------------------------ CONTRATOS ------------------------------
router.get('/contratos', async (_req, res) => {
  try {
    const { rows } = await pool.query('SELECT * FROM sin_contratos WHERE ativo ORDER BY empresa');
    const out = [];
    for (const c of rows) {
      const calc = await calcularContrato(c.id);
      out.push({ ...c, ultimo: calc.ultimo, status: calc.status, projecao_reajuste: calc.projecao_reajuste });
    }
    res.json(out);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

router.post('/contratos', async (req, res) => {
  try {
    const { empresa, cnpj, operadora, produto, vidas, break_even, mes_reajuste, vcmh_estimada } = req.body;
    if (!empresa || !operadora) return res.status(400).json({ erro: 'empresa e operadora são obrigatórios' });
    const token = crypto.randomBytes(24).toString('hex');
    const { rows: [c] } = await pool.query(
      `INSERT INTO sin_contratos (empresa,cnpj,operadora,produto,vidas,break_even,mes_reajuste,vcmh_estimada,token_cliente)
       VALUES ($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
      [empresa, cnpj || null, operadora, produto || null, vidas || 0, break_even || 70, mes_reajuste || null, vcmh_estimada || 12, token]);
    res.status(201).json(c);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

router.get('/contratos/:id', async (req, res) => {
  try {
    if (!idValido(req.params.id)) return res.status(400).json({ erro: 'id inválido' });
    const calc = await calcularContrato(req.params.id);
    if (!calc) return res.status(404).json({ erro: 'contrato não encontrado' });
    const { rows: arquivos } = await pool.query(
      'SELECT id,competencia,nome_arquivo,mime,tamanho,visivel_cliente,enviado_em FROM sin_arquivos WHERE contrato_id=$1 ORDER BY enviado_em DESC',
      [req.params.id]);
    res.json({ ...calc, arquivos });
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// Atualiza dados cadastrais/técnicos do contrato (vidas, break-even, VCMH…)
router.put('/contratos/:id', async (req, res) => {
  try {
    if (!idValido(req.params.id)) return res.status(400).json({ erro: 'id inválido' });
    const permitidos = ['empresa', 'cnpj', 'operadora', 'produto', 'vidas', 'break_even',
                        'mes_reajuste', 'vcmh_estimada', 'cronosseg_id', 'ativo'];
    const sets = [], vals = [];
    for (const campo of permitidos) {
      if (req.body[campo] !== undefined) {
        vals.push(req.body[campo]);
        sets.push(`${campo}=$${vals.length}`);
      }
    }
    if (!sets.length) return res.status(400).json({ erro: 'nenhum campo para atualizar' });
    vals.push(req.params.id);
    const { rows: [c] } = await pool.query(
      `UPDATE sin_contratos SET ${sets.join(',')} WHERE id=$${vals.length} RETURNING *`, vals);
    if (!c) return res.status(404).json({ erro: 'contrato não encontrado' });
    res.json(c);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// Regenera o token do portal (revoga o link antigo do RH imediatamente)
router.post('/contratos/:id/token', async (req, res) => {
  try {
    if (!idValido(req.params.id)) return res.status(400).json({ erro: 'id inválido' });
    const token = crypto.randomBytes(24).toString('hex');
    const { rows: [c] } = await pool.query(
      'UPDATE sin_contratos SET token_cliente=$1 WHERE id=$2 RETURNING id, token_cliente', [token, req.params.id]);
    if (!c) return res.status(404).json({ erro: 'contrato não encontrado' });
    res.json(c);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// -------------------------- LANÇAMENTOS MENSAIS --------------------------
router.post('/contratos/:id/meses', async (req, res) => {
  try {
    if (!idValido(req.params.id)) return res.status(400).json({ erro: 'id inválido' });
    const { competencia, premio, sinistro, vidas_mes, observacao } = req.body;
    const comp = normalizarCompetencia(competencia);
    if (!comp) return res.status(400).json({ erro: 'competencia inválida (use AAAA-MM)' });
    if (!(Number(premio) > 0)) return res.status(400).json({ erro: 'premio deve ser maior que zero' });
    if (Number(sinistro) < 0) return res.status(400).json({ erro: 'sinistro não pode ser negativo' });
    const { rows: [existe] } = await pool.query('SELECT 1 FROM sin_contratos WHERE id=$1', [req.params.id]);
    if (!existe) return res.status(404).json({ erro: 'contrato não encontrado' });
    const { rows: [m] } = await pool.query(
      `INSERT INTO sin_meses (contrato_id,competencia,premio,sinistro,vidas_mes,observacao)
       VALUES ($1,$2,$3,$4,$5,$6)
       ON CONFLICT (contrato_id,competencia)
       DO UPDATE SET premio=EXCLUDED.premio, sinistro=EXCLUDED.sinistro,
                     vidas_mes=EXCLUDED.vidas_mes, observacao=EXCLUDED.observacao
       RETURNING *`,
      [req.params.id, comp, premio, sinistro || 0, vidas_mes || null, observacao || null]);
    res.status(201).json(m);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

router.delete('/meses/:mesId', async (req, res) => {
  try {
    if (!idValido(req.params.mesId)) return res.status(400).json({ erro: 'id inválido' });
    await pool.query('DELETE FROM sin_meses WHERE id=$1', [req.params.mesId]);
    res.json({ ok: true });
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// ------------------------------ ARQUIVOS ------------------------------
router.post('/contratos/:id/arquivos', upload.single('relatorio'), async (req, res) => {
  try {
    if (!idValido(req.params.id)) return res.status(400).json({ erro: 'id inválido' });
    if (!req.file) return res.status(400).json({ erro: 'arquivo obrigatório (campo: relatorio)' });
    const { competencia, visivel_cliente } = req.body;
    const { rows: [a] } = await pool.query(
      `INSERT INTO sin_arquivos (contrato_id,competencia,nome_arquivo,caminho,mime,tamanho,visivel_cliente)
       VALUES ($1,$2,$3,$4,$5,$6,$7) RETURNING id,nome_arquivo,enviado_em`,
      [req.params.id, normalizarCompetencia(competencia),
       req.file.originalname, req.file.path, req.file.mimetype, req.file.size,
       visivel_cliente === 'true']);
    res.status(201).json(a);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// Download ADMIN — fica atrás do login do Diseg (não liberar do auth)
router.get('/arquivos/:arqId/download', async (req, res) => {
  try {
    if (!idValido(req.params.arqId)) return res.status(400).json({ erro: 'id inválido' });
    const { rows: [a] } = await pool.query('SELECT * FROM sin_arquivos WHERE id=$1', [req.params.arqId]);
    if (!a) return res.status(404).json({ erro: 'arquivo não encontrado' });
    res.download(a.caminho, a.nome_arquivo);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// ------------------- PORTAL DO CLIENTE (RH) — via token -------------------
// Somente leitura. LGPD: dados agregados; arquivos só se visivel_cliente=true.
router.get('/portal/:token', async (req, res) => {
  try {
    const { rows: [c] } = await pool.query(
      'SELECT id FROM sin_contratos WHERE token_cliente=$1 AND ativo', [req.params.token]);
    if (!c) return res.status(404).json({ erro: 'link inválido ou expirado' });
    const calc = await calcularContrato(c.id);
    const { rows: arquivos } = await pool.query(
      `SELECT id,competencia,nome_arquivo,enviado_em FROM sin_arquivos
        WHERE contrato_id=$1 AND visivel_cliente ORDER BY enviado_em DESC`, [c.id]);
    // Não expor token/cnpj/cronosseg no payload do cliente
    const { token_cliente, cronosseg_id, cnpj, ...contratoPublico } = calc.contrato;
    res.json({ ...calc, contrato: contratoPublico, arquivos });
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// Download do CLIENTE — valida token + pertencimento ao contrato + visivel_cliente.
// (Sem isso, qualquer pessoa com um ID sequencial baixaria relatórios com dado de saúde.)
router.get('/portal/:token/arquivos/:arqId/download', async (req, res) => {
  try {
    if (!idValido(req.params.arqId)) return res.status(400).json({ erro: 'id inválido' });
    const { rows: [a] } = await pool.query(
      `SELECT a.caminho, a.nome_arquivo
         FROM sin_arquivos a
         JOIN sin_contratos c ON c.id = a.contrato_id
        WHERE a.id=$1 AND c.token_cliente=$2 AND c.ativo AND a.visivel_cliente`,
      [req.params.arqId, req.params.token]);
    if (!a) return res.status(404).json({ erro: 'arquivo não encontrado' });
    res.download(a.caminho, a.nome_arquivo);
  } catch (e) { res.status(500).json({ erro: e.message }); }
});

// ---------------- INTEGRAÇÃO CRONOSSEG (stub preparado) ----------------
// CronosSeg roda em MySQL na Locaweb (cronosseg2018.mysql.dbaas.com.br).
// Quando as credenciais forem confirmadas, implementar sync aqui:
//   npm install mysql2 --save
//   Mapear apólice CronosSeg -> sin_contratos.cronosseg_id
router.post('/sync/cronosseg', (_req, res) => {
  res.status(501).json({
    erro: 'Integração CronosSeg pendente de credenciais MySQL (Locaweb). Nada foi sincronizado.',
    protocolo: 'DCG Protocolo Verdade — sem dados inventados'
  });
});

// Erros de upload (multer) e demais erros síncronos viram JSON, não HTML
router.use((err, _req, res, _next) => {
  res.status(err.status || 400).json({ erro: err.message || 'erro no processamento' });
});

module.exports = router;
