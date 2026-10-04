#!/usr/bin/env python3
"""
Importa os dados reais (CronosSeg, Vitalício, Espigão) para o Supabase do
Painel Completo DCG, e cria/atualiza o usuário de login do painel.

ESTE SCRIPT NÃO CONTÉM DADOS DE CLIENTES. Rode-o na VPS, numa pasta que
contenha os 4 arquivos .json que o Diniz recebeu separadamente (nunca
commitados no repositório público):
  - contratos_cronosseg.json
  - contratos_vitalicio.json
  - empresas_espigao.json
  - decisores_espigao.json

Uso na VPS:
  export SUPABASE_SERVICE_ROLE_KEY='sb_secret_...'   # cole aqui, nunca no chat
  python3 importar-dados.py

Variáveis opcionais:
  SUPABASE_URL            (padrão: projeto de produção do painel)
  DCG_LOGIN_EMAIL         (padrão: dcgseguros@gmail.com)
  DCG_LOGIN_PASSWORD      (padrão: dcg2026)
  DADOS_DIR               (padrão: pasta atual)
"""
import json
import os
import sys
import urllib.request
import urllib.error

SUPABASE_URL = os.environ.get("SUPABASE_URL", "https://lleyoetkisvtfmmypnei.supabase.co")
SERVICE_KEY = os.environ.get("SUPABASE_SERVICE_ROLE_KEY", "").strip()
LOGIN_EMAIL = os.environ.get("DCG_LOGIN_EMAIL", "dcgseguros@gmail.com")
LOGIN_PASSWORD = os.environ.get("DCG_LOGIN_PASSWORD", "dcg2026")
DADOS_DIR = os.environ.get("DADOS_DIR", ".")
BATCH = 500

if not SERVICE_KEY:
    sys.exit(
        "Erro: defina SUPABASE_SERVICE_ROLE_KEY antes de rodar.\n"
        "Exemplo: export SUPABASE_SERVICE_ROLE_KEY='sb_secret_...'"
    )


def req(method, path, body=None, headers=None, base=None):
    url = (base or SUPABASE_URL) + path
    data = json.dumps(body).encode("utf-8") if body is not None else None
    h = {
        "apikey": SERVICE_KEY,
        "Authorization": f"Bearer {SERVICE_KEY}",
        "Content-Type": "application/json",
    }
    if headers:
        h.update(headers)
    r = urllib.request.Request(url, data=data, headers=h, method=method)
    try:
        with urllib.request.urlopen(r) as resp:
            raw = resp.read()
            return resp.status, (json.loads(raw) if raw else None)
    except urllib.error.HTTPError as e:
        raw = e.read()
        try:
            parsed = json.loads(raw)
        except Exception:
            parsed = raw.decode("utf-8", "replace")
        return e.code, parsed


def load(name):
    path = os.path.join(DADOS_DIR, name)
    if not os.path.exists(path):
        print(f"   aviso: {name} não encontrado em {DADOS_DIR}, pulando.")
        return []
    with open(path, encoding="utf-8") as f:
        return json.load(f)


def post_batches(table, rows, prefer):
    ok, fail = 0, 0
    for i in range(0, len(rows), BATCH):
        chunk = rows[i : i + BATCH]
        status, body = req("POST", f"/rest/v1/{table}", chunk, {"Prefer": prefer})
        if status in (200, 201):
            ok += len(chunk)
        else:
            fail += len(chunk)
            print(f"   lote {i}-{i+len(chunk)} falhou ({status}): {str(body)[:300]}")
    return ok, fail


def get_all_empresas_map():
    mapping = {}
    offset = 0
    page = 1000
    while True:
        status, body = req(
            "GET",
            f"/rest/v1/empresas?select=id,cnpj&limit={page}&offset={offset}",
        )
        if status not in (200,) or not body:
            break
        for row in body:
            if row.get("cnpj"):
                mapping[row["cnpj"]] = row["id"]
        if len(body) < page:
            break
        offset += page
    return mapping


def criar_ou_atualizar_login():
    print("==> Configurando login do painel...")
    status, body = req(
        "POST",
        "/auth/v1/admin/users",
        {"email": LOGIN_EMAIL, "password": LOGIN_PASSWORD, "email_confirm": True},
    )
    if status in (200, 201):
        print(f"   usuário {LOGIN_EMAIL} criado com sucesso.")
        return
    msg = str(body)
    if status == 422 or "already" in msg.lower() or "exists" in msg.lower():
        print(f"   usuário {LOGIN_EMAIL} já existia — atualizando a senha...")
        status2, body2 = req("GET", f"/auth/v1/admin/users?email={LOGIN_EMAIL}")
        user_id = None
        if status2 == 200 and body2:
            users = body2.get("users", body2) if isinstance(body2, dict) else body2
            if isinstance(users, list):
                for u in users:
                    if u.get("email") == LOGIN_EMAIL:
                        user_id = u.get("id")
                        break
        if user_id:
            status3, body3 = req(
                "PUT",
                f"/auth/v1/admin/users/{user_id}",
                {"password": LOGIN_PASSWORD, "email_confirm": True},
            )
            if status3 in (200, 201):
                print("   senha atualizada com sucesso.")
            else:
                print(f"   falha ao atualizar senha ({status3}): {str(body3)[:300]}")
        else:
            print("   não foi possível localizar o ID do usuário para atualizar a senha.")
            print(f"   resposta da busca: {str(body2)[:300]}")
    else:
        print(f"   falha ao criar usuário ({status}): {msg[:300]}")


def main():
    print(f"==> Importando dados para {SUPABASE_URL}")

    contratos = load("contratos_cronosseg.json") + load("contratos_vitalicio.json")
    if contratos:
        print(f"==> Enviando {len(contratos)} contratos (CronosSeg + Vitalício)...")
        ok, fail = post_batches("contratos", contratos, "return=minimal")
        print(f"   contratos: {ok} inseridos, {fail} falharam.")

    empresas = load("empresas_espigao.json")
    if empresas:
        print(f"==> Enviando {len(empresas)} empresas (Espigão)...")
        ok, fail = post_batches(
            "empresas", empresas, "resolution=merge-duplicates,return=minimal"
        )
        print(f"   empresas: {ok} inseridas/atualizadas, {fail} falharam.")

    decisores_raw = load("decisores_espigao.json")
    if decisores_raw:
        print("==> Resolvendo vínculo empresa_id (por CNPJ) para os decisores...")
        cnpj_to_id = get_all_empresas_map()
        print(f"   {len(cnpj_to_id)} empresas mapeadas por CNPJ no banco.")

        decisores = []
        sem_match = 0
        for d in decisores_raw:
            cnpj_ref = d.get("cnpj_ref")
            empresa_id = cnpj_to_id.get(cnpj_ref)
            if not empresa_id:
                sem_match += 1
                continue
            row = {k: v for k, v in d.items() if k != "cnpj_ref"}
            row["empresa_id"] = empresa_id
            decisores.append(row)

        print(f"   {len(decisores)} decisores com empresa vinculada, {sem_match} sem correspondência (ignorados).")
        if decisores:
            print(f"==> Enviando {len(decisores)} decisores...")
            ok, fail = post_batches("decisores", decisores, "return=minimal")
            print(f"   decisores: {ok} inseridos, {fail} falharam.")

    criar_ou_atualizar_login()

    print("\n==> Importação concluída. Confira os totais acima.")


if __name__ == "__main__":
    main()
