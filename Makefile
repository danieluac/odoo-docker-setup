# ═════════════════════════════════════════════════════════════════════
# Odoo · Ambiente Docker — interface única: make
#
# Quem não sabe Docker só precisa disto:
#
#     make up                              # sobe o ambiente (Odoo + Postgres)
#     make backup                          # backup da BD activa (com filestore)
#     make restore FILE=backups/prod.zip   # restaura um backup (fica a BD activa)
#     make help                            # todos os comandos
#
# TODA a configuração (versão do Odoo, porta, credenciais…) vem do .env —
# criado automaticamente a partir do .env.example na 1ª execução e nunca
# sobrescrito. Para mudar a versão do Odoo: edita ODOO_VERSION no .env e
# corre `make up` (cada versão tem containers/volumes/BDs isolados).
# ═════════════════════════════════════════════════════════════════════

SHELL := /bin/bash
# -e: cada receita falha à primeira falha — usar `|| true` onde a falha é aceitável
.SHELLFLAGS := -ec
.ONESHELL:
.DEFAULT_GOAL := help

ROOT_DIR := $(abspath $(dir $(lastword $(MAKEFILE_LIST))))
ENV_FILE := $(ROOT_DIR)/.env
comma := ,

# env(KEY) — lê uma variável do .env (a ÚNICA fonte de configuração).
# Recursivo (avaliado só quando usado, já depois do `init` criar o .env).
env = $(strip $(shell [ -f $(ENV_FILE) ] && sed -nE 's/^[[:space:]]*$(1)[[:space:]]*=[[:space:]]*//p' $(ENV_FILE) | tail -1))

# ── Configuração (tudo vem do .env) ──────────────────────────────────
ODOO_VERSION     = $(call env,ODOO_VERSION)
POSTGRES_VERSION = $(call env,POSTGRES_VERSION)
ODOO_PORT        = $(call env,ODOO_PORT)
PGUSER           = $(call env,POSTGRES_USER)
ENTERPRISE_DIR   = $(call env,ENTERPRISE_DIR)
BACKUP_RAW       = $(call env,BACKUP_DIR)
BACKUP_ABS       = $(if $(filter /%,$(BACKUP_RAW)),$(BACKUP_RAW),$(abspath $(ROOT_DIR)/$(if $(BACKUP_RAW),$(BACKUP_RAW),backups)))

# ── Parâmetros por comando (argumentos, não configuração) ────────────
FILE       ?=
MODULE     ?=
FILESTORE  ?= 1
NEUTRALIZE ?= 1
DB_FROM_CLI := $(if $(filter command line,$(origin DB)),1,)
# BD alvo: DB=<nome> na CLI > derivada do FILE (restore) > ODOO_DB do .env
ifneq ($(origin DB),command line)
DB = $(or $(if $(FILE),$(basename $(notdir $(FILE)))),$(call env,ODOO_DB))
endif

# ── docker compose: um projecto por versão → ambientes isolados ──────
PROJECT = odoo-$(subst .,-,$(ODOO_VERSION))
COMPOSE_FILES = -f $(ROOT_DIR)/docker-compose.yml \
  $(if $(filter 1,$(call env,PG_TUNING)),-f $(ROOT_DIR)/docker-compose.pg-tuning.yml,) \
  $(if $(ENTERPRISE_DIR),-f $(ROOT_DIR)/docker-compose.enterprise.yml,)
COMPOSE  = docker compose --project-directory $(ROOT_DIR) -p $(PROJECT) $(COMPOSE_FILES)
EXEC_DB  = $(COMPOSE) exec -T db
PSQL     = $(EXEC_DB) psql -U $(PGUSER)
# one-off: container descartável do serviço odoo (não mexe no servidor)
RUN_ODOO = $(COMPOSE) run --rm -T --no-deps odoo

# ── Cores ────────────────────────────────────────────────────────────
C_CYAN  := \033[0;36m
C_GREEN := \033[0;32m
C_YELL  := \033[0;33m
C_RED   := \033[0;31m
C_BOLD  := \033[1m
C_DIM   := \033[2m
C_RESET := \033[0m

# ═════════════════════════════════════════════════════════════════════
# Help
# ═════════════════════════════════════════════════════════════════════
.PHONY: help
help:  ## Mostra esta ajuda
	@printf "$(C_BOLD)Odoo · ambiente Docker$(C_RESET)  $(C_DIM)(versão: $(if $(ODOO_VERSION),$(ODOO_VERSION),— corre make up) · BD activa: $(if $(DB),$(DB),—))$(C_RESET)\n\n"
	@awk 'BEGIN {FS = ":.*?## "} /^[a-zA-Z_.%-]+:.*?## / { \
		printf "  $(C_CYAN)%-14s$(C_RESET) %s\n", $$1, $$2 \
	}' $(MAKEFILE_LIST)
	@printf "\n$(C_DIM)Parâmetros:$(C_RESET) DB=<nome>  FILE=<backup>  MODULE=<a,b,c>  FILESTORE=0  NEUTRALIZE=0\n"
	@printf "$(C_DIM)Exemplos:$(C_RESET)\n"
	@printf "  make up                                # sobe tudo (1ª vez cria o .env e demora mais)\n"
	@printf "  make backup                            # backup da BD activa com filestore → backups/\n"
	@printf "  make backup DB=outra FILESTORE=0       # backup doutra BD, sem filestore\n"
	@printf "  make restore FILE=backups/prod.zip     # restaura; a BD 'prod' fica activa\n"
	@printf "  make scaffold MODULE=minha_app         # cria a estrutura de um módulo novo em addons/\n"
	@printf "  make debug                             # sobe com debugpy em :5678 (attach do VS Code)\n"
	@printf "\n$(C_DIM)Configuração (versão do Odoo, porta, credenciais…): edita o .env e corre make up$(C_RESET)\n"

# ═════════════════════════════════════════════════════════════════════
# Pré-requisitos e ficheiros gerados
# ═════════════════════════════════════════════════════════════════════
.PHONY: guard
guard:
	@command -v docker >/dev/null 2>&1 || { printf "$(C_RED)✗ Docker não está instalado$(C_RESET) — instala em https://docs.docker.com/get-docker/\n"; exit 1; }
	docker info >/dev/null 2>&1 || { printf "$(C_RED)✗ o Docker não está a correr$(C_RESET) — abre o Docker Desktop (ou: sudo systemctl start docker)\n"; exit 1; }
	docker compose version >/dev/null 2>&1 || { printf "$(C_RED)✗ falta o Docker Compose v2$(C_RESET) — vem incluído no Docker Desktop / plugin docker-compose-v2\n"; exit 1; }

.PHONY: init
init:  ## Cria o .env (a partir do .env.example) e as pastas — idempotente
	@if [ ! -f $(ENV_FILE) ]; then
		cp $(ROOT_DIR)/.env.example $(ENV_FILE)
		printf "$(C_GREEN)✓ .env criado a partir do .env.example$(C_RESET) $(C_DIM)(edita-o para mudar versão/porta/credenciais — nunca é sobrescrito)$(C_RESET)\n"
	fi
	mkdir -p $(ROOT_DIR)/addons $(ROOT_DIR)/config $(ROOT_DIR)/backups

# valida que as variáveis obrigatórias existem e não estão vazias no .env
.PHONY: check-env
check-env: init
	@missing=0
	for v in ODOO_VERSION POSTGRES_VERSION ODOO_PORT ODOO_DB POSTGRES_USER POSTGRES_PASSWORD ADMIN_PASSWD ODOO_LOG ODOO_DEV ODOO_DEBUG_PORT; do
		if ! grep -qE "^[[:space:]]*$$v[[:space:]]*=[[:space:]]*[^[:space:]]" $(ENV_FILE); then
			printf "$(C_RED)✗ variável $$v em falta ou vazia no .env$(C_RESET)\n"
			missing=1
		fi
	done
	[ $$missing -eq 0 ] || { printf "$(C_DIM)  compara o teu .env com o .env.example$(C_RESET)\n"; exit 1; }

# ── Templates do make scaffold (placeholders @X@ substituídos na receita) ──
define SCAFFOLD_MANIFEST
{
    'name': '@TITLE@',
    'summary': 'Resumo curto do que o módulo faz',
    'description': """
Descrição longa do módulo @MODULE@.
""",
    'author': '@AUTHOR@',
    'website': '@WEBSITE@',
    'contributors': [@CONTRIB@],
    'category': 'Uncategorized',
    'version': '@VERSION@',
    'license': 'LGPL-3',
    'depends': ['base'],
    'data': [
        'security/ir.model.access.csv',
        'views/views.xml',
    ],
    'application': False,
    'installable': True,
}
endef
export SCAFFOLD_MANIFEST

define SCAFFOLD_MODELS
from odoo import models, fields  # noqa: F401


# Exemplo de modelo — descomenta e adapta:
#
# class @CLASS@(models.Model):
#     _name = '@MODULE@.@MODULE@'
#     _description = '@TITLE@'
#
#     name = fields.Char(string='Nome', required=True)
endef
export SCAFFOLD_MODELS

define SCAFFOLD_VIEWS
<?xml version="1.0" encoding="utf-8"?>
<odoo>
    <!-- Vistas, menus e acções do módulo @MODULE@.
         Exemplo de acção + menu (descomenta e adapta):

    <record id="action_@MODULE@" model="ir.actions.act_window">
        <field name="name">@TITLE@</field>
        <field name="res_model">@MODULE@.@MODULE@</field>
        <field name="view_mode">tree,form</field>
    </record>
    <menuitem id="menu_@MODULE@" name="@TITLE@" action="action_@MODULE@"/>
    -->
</odoo>
endef
export SCAFFOLD_VIEWS

define SCAFFOLD_README
# @TITLE@

Descrição do módulo @MODULE@.

Instalação no ambiente: `make install MODULE=@MODULE@`
endef
export SCAFFOLD_README

# odoo.conf — derivado do .env, regenerado em cada make up (não editar)
define ODOO_CONF_CONTENT
# GERADO automaticamente pelo make a partir do .env — NÃO editar aqui.
# Para mudar a configuração: edita o .env e corre `make up`.
[options]
admin_passwd = $(call env,ADMIN_PASSWD)
db_host = db
db_port = 5432
db_user = $(call env,POSTGRES_USER)
db_password = $(call env,POSTGRES_PASSWORD)
addons_path = $(if $(ENTERPRISE_DIR),/mnt/enterprise$(comma),)/mnt/extra-addons
data_dir = /var/lib/odoo
workers = 0
max_cron_threads = 1
limit_time_cpu = 3600
limit_time_real = 3600
limit_memory_soft = 2147483648
limit_memory_hard = 4294967296
list_db = True
endef
export ODOO_CONF_CONTENT

.PHONY: conf
conf: init
	@echo "$$ODOO_CONF_CONTENT" > $(ROOT_DIR)/config/odoo.conf

# garante que a imagem odoo-custom:<versão> existe (constrói na 1ª vez)
.PHONY: ensure-image
ensure-image: guard check-env
	@if ! docker image inspect odoo-custom:$(ODOO_VERSION) >/dev/null 2>&1; then
		printf "$(C_CYAN)→ 1ª utilização da versão $(ODOO_VERSION) — a construir a imagem (demora uns minutos)$(C_RESET)\n"
		$(COMPOSE) build odoo
	fi

# ═════════════════════════════════════════════════════════════════════
# Ambiente
# ═════════════════════════════════════════════════════════════════════
.PHONY: up
up: guard check-env conf  ## Sobe o ambiente completo (Odoo + Postgres) — 1ª vez demora
	@printf "$(C_CYAN)→ a construir a imagem Odoo $(ODOO_VERSION) (rápido se nada mudou)$(C_RESET)\n"
	$(COMPOSE) build odoo
	printf "$(C_CYAN)→ a subir o Postgres$(C_RESET)\n"
	$(COMPOSE) up -d --wait db
	if ! $(PSQL) -d "$(DB)" -tAc "SELECT 1 FROM information_schema.tables WHERE table_name='ir_module_module'" 2>/dev/null | grep -q 1; then
		printf "$(C_CYAN)→ BD $(DB) não existe — a inicializar com os módulos base (demora uns minutos)$(C_RESET)\n"
		$(RUN_ODOO) odoo -d $(DB) -i base --stop-after-init --log-level warn
	fi
	printf "$(C_CYAN)→ a subir o Odoo$(C_RESET)\n"
	$(COMPOSE) up -d odoo
	printf "\n$(C_GREEN)✓ ambiente pronto$(C_RESET) → $(C_BOLD)http://localhost:$(ODOO_PORT)$(C_RESET)  (Odoo $(ODOO_VERSION) · BD: $(DB) · login: admin / admin)\n"

.PHONY: debug
debug: guard check-env conf ensure-image  ## Sobe com debugpy à escuta (attach do VS Code, config "Odoo")
	@printf "$(C_CYAN)→ a subir em modo debug (debugpy em :$(call env,ODOO_DEBUG_PORT), sem auto-reload)$(C_RESET)\n"
	$(COMPOSE) up -d --wait db
	ODOO_DEBUG=1 ODOO_DEV=qweb,xml $(COMPOSE) up -d odoo
	printf "$(C_GREEN)✓ debugpy à escuta em :$(call env,ODOO_DEBUG_PORT)$(C_RESET) — attach pelo VS Code (F5, config \"Odoo\")\n"
	printf "$(C_DIM)  nota: o auto-reload fica desligado em debug; make up volta ao modo normal$(C_RESET)\n"

.PHONY: down
down: guard init  ## Pára o ambiente (os dados persistem nos volumes)
	@$(COMPOSE) down
	printf "$(C_GREEN)✓ parado$(C_RESET) (make up para voltar — os dados mantêm-se)\n"

.PHONY: restart
restart: guard check-env conf  ## Reinicia o servidor Odoo (aplica mudanças do .env)
	@$(COMPOSE) up -d --force-recreate odoo
	printf "$(C_GREEN)✓ odoo reiniciado$(C_RESET)\n"

.PHONY: logs
logs: guard init  ## Segue os logs do Odoo (Ctrl-C para sair)
	@$(COMPOSE) logs -f --tail=100 odoo

.PHONY: logs-db
logs-db: guard init  ## Segue os logs do Postgres
	@$(COMPOSE) logs -f --tail=100 db

.PHONY: status
status: guard init  ## Estado do ambiente (versão, BD activa, containers)
	@printf "$(C_BOLD)Ambiente$(C_RESET)\n"
	printf "  $(C_DIM)Odoo:$(C_RESET)      $(ODOO_VERSION)\n"
	printf "  $(C_DIM)BD activa:$(C_RESET) $(call env,ODOO_DB)\n"
	printf "  $(C_DIM)URL:$(C_RESET)       http://localhost:$(ODOO_PORT)\n"
	printf "\n$(C_BOLD)Containers$(C_RESET)\n"
	$(COMPOSE) ps

.PHONY: destroy
destroy: guard check-env  ## APAGA o ambiente da versão actual: containers + volumes + BDs (confirmação)
	@read -p "Apagar containers e TODOS os dados (BDs + filestore) do Odoo $(ODOO_VERSION)? [y/N] " c
	[ "$$c" = "y" ] || { echo "abortado"; exit 1; }
	$(COMPOSE) down -v --remove-orphans
	printf "$(C_GREEN)✓ ambiente Odoo $(ODOO_VERSION) destruído$(C_RESET) (as outras versões não foram tocadas)\n"

# ═════════════════════════════════════════════════════════════════════
# Backups
# ═════════════════════════════════════════════════════════════════════
.PHONY: backup
backup: guard check-env conf ensure-image  ## Backup da BD em zip formato Odoo (FILESTORE=0 → sem filestore; DB=<nome> outra BD)
	@$(COMPOSE) up -d --wait db
	DBNAME="$(DB)"
	if [ "$$($(PSQL) -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$$DBNAME'")" != "1" ]; then
		printf "$(C_RED)✗ a BD $$DBNAME não existe$(C_RESET) (vê as existentes com: make db-list)\n"
		exit 1
	fi
	mkdir -p $(BACKUP_ABS)
	NAME="$${DBNAME}_$$(date +%Y%m%d_%H%M%S)$(if $(filter 0,$(FILESTORE)),_sem-filestore,).zip"
	printf "$(C_CYAN)→ a criar backup $$NAME $(if $(filter 0,$(FILESTORE)),(sem filestore),(com filestore)) — pode demorar$(C_RESET)\n"
	$(EXEC_DB) pg_dump -U $(PGUSER) --no-owner "$$DBNAME" \
		| $(COMPOSE) run --rm -T --no-deps --user root \
			-v $(BACKUP_ABS):/backup \
			-e BACKUP_UID=$$(id -u) -e BACKUP_GID=$$(id -g) \
			odoo python3 /mnt/scripts/backup_util.py zip "/backup/$$NAME" "$$DBNAME" "$(FILESTORE)" "$(ODOO_VERSION)" "$(POSTGRES_VERSION)"
	test $${PIPESTATUS[0]} -eq 0 || { rm -f "$(BACKUP_ABS)/$$NAME"; printf "$(C_RED)✗ pg_dump falhou$(C_RESET)\n"; exit 1; }
	printf "$(C_GREEN)✓ backup criado:$(C_RESET) $(BACKUP_ABS)/$$NAME ($$(du -h "$(BACKUP_ABS)/$$NAME" | cut -f1))\n"
	printf "$(C_DIM)  formato zip padrão do Odoo — restaurável com make restore ou pela UI do Odoo$(C_RESET)\n"

.PHONY: backup-list
backup-list: init  ## Lista os backups existentes
	@ls -lht $(BACKUP_ABS)/*.zip 2>/dev/null || printf "$(C_DIM)(nenhum backup em $(BACKUP_ABS) — cria um com: make backup)$(C_RESET)\n"

.PHONY: restore
restore: guard check-env conf ensure-image  ## Restaura um backup (FILE=<.zip|.sql|.dump> [DB=nome]) — a BD fica activa
	@test -n "$(FILE)" || { printf "$(C_RED)✗ uso: make restore FILE=backups/<ficheiro>.zip [DB=nome]$(C_RESET)\n"; exit 1; }
	test -f "$(FILE)" || { printf "$(C_RED)✗ ficheiro não encontrado: $(FILE)$(C_RESET)\n"; exit 1; }
	SRC="$$(cd "$$(dirname "$(FILE)")" && pwd)/$$(basename "$(FILE)")"
	DBNAME="$(DB)"
	printf "$(C_CYAN)→ restore de $(FILE) para a BD $$DBNAME$(C_RESET)\n"
	$(COMPOSE) stop odoo 2>/dev/null || true
	$(COMPOSE) up -d --wait db
	$(PSQL) -d postgres -q -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$$DBNAME' AND pid<>pg_backend_pid();" >/dev/null 2>&1 || true
	$(PSQL) -d postgres -q -c "DROP DATABASE IF EXISTS \"$$DBNAME\";"
	$(PSQL) -d postgres -q -c "CREATE DATABASE \"$$DBNAME\" OWNER \"$(PGUSER)\";"
	case "$$SRC" in
	*.zip)
		$(COMPOSE) run --rm -T --no-deps -v "$$SRC":/backup.zip:ro odoo python3 /mnt/scripts/backup_util.py check /backup.zip
		printf "$(C_CYAN)→ a importar dump.sql (streaming — pode demorar)$(C_RESET)\n"
		$(COMPOSE) run --rm -T --no-deps -v "$$SRC":/backup.zip:ro odoo python3 /mnt/scripts/backup_util.py cat /backup.zip dump.sql \
			| $(PSQL) -q -d "$$DBNAME" -v ON_ERROR_STOP=0 >/dev/null
		test $${PIPESTATUS[0]} -eq 0 || { printf "$(C_RED)✗ leitura do zip falhou$(C_RESET)\n"; exit 1; }
		if $(COMPOSE) run --rm -T --no-deps -v "$$SRC":/backup.zip:ro odoo python3 /mnt/scripts/backup_util.py has-filestore /backup.zip; then
			printf "$(C_CYAN)→ a repor o filestore$(C_RESET)\n"
			$(COMPOSE) run --rm -T --no-deps --user root -v "$$SRC":/backup.zip:ro odoo python3 /mnt/scripts/backup_util.py extract-filestore /backup.zip "$$DBNAME"
		else
			printf "$(C_DIM)— zip sem filestore (backup só-BD)$(C_RESET)\n"
		fi
		;;
	*.sql)
		printf "$(C_CYAN)→ a importar $$SRC$(C_RESET)\n"
		cat "$$SRC" | $(PSQL) -q -d "$$DBNAME" -v ON_ERROR_STOP=0 >/dev/null
		test $${PIPESTATUS[0]} -eq 0 || { printf "$(C_RED)✗ leitura do .sql falhou$(C_RESET)\n"; exit 1; }
		;;
	*.dump)
		printf "$(C_CYAN)→ a importar $$SRC (pg_restore)$(C_RESET)\n"
		$(EXEC_DB) pg_restore -U $(PGUSER) -d "$$DBNAME" --no-owner < "$$SRC" || true
		;;
	*)
		printf "$(C_RED)✗ formato não suportado (usa .zip do Odoo, .sql ou .dump)$(C_RESET)\n"
		exit 1
		;;
	esac
	if [ "$(NEUTRALIZE)" = "1" ]; then
		printf "$(C_CYAN)→ a neutralizar a BD para dev (crons + email desligados; NEUTRALIZE=0 evita)$(C_RESET)\n"
		$(PSQL) -d "$$DBNAME" -q -c "UPDATE ir_cron SET active = false;" 2>/dev/null || true
		$(PSQL) -d "$$DBNAME" -q -c "UPDATE ir_mail_server SET active = false;" 2>/dev/null || true
		$(PSQL) -d "$$DBNAME" -q -c "UPDATE fetchmail_server SET active = false;" 2>/dev/null || true
	fi
	$(MAKE) --no-print-directory _set-active-db DBSET="$$DBNAME"
	$(COMPOSE) up -d odoo
	printf "$(C_GREEN)✓ BD $$DBNAME restaurada e activa$(C_RESET) → http://localhost:$(ODOO_PORT)\n"
	printf "$(C_DIM)  se o backup vier de outra versão do código: make update MODULE=all$(C_RESET)\n"

# grava ODOO_DB=<DBSET> no .env (BD activa) — sed portável (Linux e macOS)
.PHONY: _set-active-db
_set-active-db:
	@if grep -qE '^[[:space:]]*ODOO_DB[[:space:]]*=' $(ENV_FILE); then
		sed -E 's/^[[:space:]]*ODOO_DB[[:space:]]*=.*/ODOO_DB=$(DBSET)/' $(ENV_FILE) > $(ENV_FILE).tmp && mv $(ENV_FILE).tmp $(ENV_FILE)
	else
		echo "ODOO_DB=$(DBSET)" >> $(ENV_FILE)
	fi
	printf "$(C_DIM)— ODOO_DB=$(DBSET) gravado no .env (é agora a BD activa)$(C_RESET)\n"

# ═════════════════════════════════════════════════════════════════════
# Bases de dados
# ═════════════════════════════════════════════════════════════════════
.PHONY: db-list
db-list: guard check-env  ## Lista as bases de dados desta versão
	@$(COMPOSE) up -d --wait db >/dev/null 2>&1 || $(COMPOSE) up -d --wait db
	$(PSQL) -d postgres -tAc "SELECT datname FROM pg_database WHERE NOT datistemplate AND datname <> 'postgres' ORDER BY 1"

.PHONY: db-use
db-use: guard check-env  ## Muda a BD activa (DB=<nome>) sem restaurar nada
	@test -n "$(DB_FROM_CLI)" || { printf "$(C_RED)✗ uso: make db-use DB=<nome>$(C_RESET)\n"; exit 1; }
	$(COMPOSE) up -d --wait db
	if [ "$$($(PSQL) -d postgres -tAc "SELECT 1 FROM pg_database WHERE datname='$(DB)'")" != "1" ]; then
		printf "$(C_RED)✗ a BD $(DB) não existe$(C_RESET) (make db-list)\n"
		exit 1
	fi
	$(MAKE) --no-print-directory _set-active-db DBSET="$(DB)"
	$(COMPOSE) up -d odoo
	printf "$(C_GREEN)✓ BD activa: $(DB)$(C_RESET) → http://localhost:$(ODOO_PORT)\n"

.PHONY: db-drop
db-drop: guard check-env  ## Apaga uma BD e o seu filestore (DB=<nome>) — pede confirmação
	@test -n "$(DB_FROM_CLI)" || { printf "$(C_RED)✗ uso: make db-drop DB=<nome>$(C_RESET)\n"; exit 1; }
	read -p "Apagar DEFINITIVAMENTE a base de dados $(DB)? [y/N] " c
	[ "$$c" = "y" ] || { echo "abortado"; exit 1; }
	$(COMPOSE) up -d --wait db
	if [ "$(DB)" = "$(call env,ODOO_DB)" ]; then
		$(COMPOSE) stop odoo 2>/dev/null || true
		printf "$(C_YELL)! estás a apagar a BD activa — depois corre make up (recria) ou make db-use DB=<outra>$(C_RESET)\n"
	fi
	$(PSQL) -d postgres -q -c "SELECT pg_terminate_backend(pid) FROM pg_stat_activity WHERE datname='$(DB)' AND pid<>pg_backend_pid();" >/dev/null 2>&1 || true
	$(PSQL) -d postgres -q -c "DROP DATABASE IF EXISTS \"$(DB)\";"
	$(COMPOSE) run --rm -T --no-deps --user root odoo rm -rf /var/lib/odoo/filestore/$(DB) 2>/dev/null || true
	printf "$(C_GREEN)✓ BD $(DB) apagada$(C_RESET)\n"

.PHONY: psql
psql: guard check-env  ## Abre um terminal SQL (psql) na BD activa
	@$(COMPOSE) exec db psql -U $(PGUSER) -d $(DB)

.PHONY: neutralize
neutralize: guard check-env  ## Desliga crons + servidores de email na BD (seguro para cópias de produção)
	@$(COMPOSE) up -d --wait db
	$(PSQL) -d "$(DB)" -q -c "UPDATE ir_cron SET active = false;" 2>/dev/null || true
	$(PSQL) -d "$(DB)" -q -c "UPDATE ir_mail_server SET active = false;" 2>/dev/null || true
	$(PSQL) -d "$(DB)" -q -c "UPDATE fetchmail_server SET active = false;" 2>/dev/null || true
	printf "$(C_GREEN)✓ BD $(DB) neutralizada$(C_RESET) (crons e email desligados)\n"

# ═════════════════════════════════════════════════════════════════════
# Odoo — módulos e shell
# ═════════════════════════════════════════════════════════════════════
.PHONY: shell
shell: guard check-env  ## Abre o odoo shell na BD activa (o ambiente tem de estar a correr)
	@$(COMPOSE) exec odoo odoo shell -d $(DB) --no-http

.PHONY: install
install: guard check-env conf ensure-image  ## Instala módulo(s): MODULE=a,b,c
	@test -n "$(MODULE)" || { printf "$(C_RED)✗ uso: make install MODULE=<nome[,nome…]>$(C_RESET)\n"; exit 1; }
	$(COMPOSE) up -d --wait db
	$(RUN_ODOO) odoo -d $(DB) -i $(MODULE) --stop-after-init --log-level info
	$(COMPOSE) restart odoo 2>/dev/null || true
	printf "$(C_GREEN)✓ módulo(s) $(MODULE) instalado(s) na BD $(DB)$(C_RESET)\n"

.PHONY: update
update: guard check-env conf ensure-image  ## Actualiza módulo(s): MODULE=a,b,c ou MODULE=all
	@test -n "$(MODULE)" || { printf "$(C_RED)✗ uso: make update MODULE=<nome[,nome…]|all>$(C_RESET)\n"; exit 1; }
	$(COMPOSE) up -d --wait db
	$(RUN_ODOO) odoo -d $(DB) -u $(MODULE) --stop-after-init --log-level info
	$(COMPOSE) restart odoo 2>/dev/null || true
	printf "$(C_GREEN)✓ módulo(s) $(MODULE) actualizado(s) na BD $(DB)$(C_RESET)\n"

.PHONY: scaffold
scaffold: init  ## Cria a estrutura de um módulo novo em addons/ (MODULE=nome_do_modulo)
	@test -n "$(MODULE)" || { printf "$(C_RED)✗ uso: make scaffold MODULE=<nome_do_modulo>$(C_RESET) $(C_DIM)(minúsculas e _, ex.: minha_app)$(C_RESET)\n"; exit 1; }
	echo "$(MODULE)" | grep -qE '^[a-z][a-z0-9_]*$$' || { printf "$(C_RED)✗ nome inválido: usa minúsculas, números e _ (ex.: minha_app)$(C_RESET)\n"; exit 1; }
	DIR=$(ROOT_DIR)/addons/$(MODULE)
	test ! -e "$$DIR" || { printf "$(C_RED)✗ addons/$(MODULE) já existe$(C_RESET)\n"; exit 1; }
	# garante a identidade no .env (acrescenta os defaults se as chaves faltarem,
	# p.ex. num .env criado por uma versão anterior do setup)
	for kv in "MODULE_AUTHOR=A Minha Empresa" "MODULE_WEBSITE=https://www.example.com" "MODULE_CONTRIBUTORS="; do
		k=$${kv%%=*}
		if ! grep -qE "^[[:space:]]*$$k[[:space:]]*=" $(ENV_FILE); then
			echo "$$kv" >> $(ENV_FILE)
			printf "$(C_YELL)! $$k acrescentado ao .env com o valor por omissão — edita-o$(C_RESET)\n"
		fi
	done
	AUTHOR="$$(sed -nE 's/^[[:space:]]*MODULE_AUTHOR[[:space:]]*=[[:space:]]*//p' $(ENV_FILE) | tail -1)"
	WEBSITE="$$(sed -nE 's/^[[:space:]]*MODULE_WEBSITE[[:space:]]*=[[:space:]]*//p' $(ENV_FILE) | tail -1)"
	CONTRIB="$$(sed -nE 's/^[[:space:]]*MODULE_CONTRIBUTORS[[:space:]]*=[[:space:]]*//p' $(ENV_FILE) | tail -1)"
	# "Ana, Rui" → 'Ana', 'Rui' (lista python no manifesto)
	if [ -n "$$CONTRIB" ]; then
		CONTRIB_PY="'$$(echo "$$CONTRIB" | sed -E "s/[[:space:]]*,[[:space:]]*/', '/g")'"
	else
		CONTRIB_PY=""
	fi
	# minha_app → "Minha App" (nome apresentável) e "MinhaApp" (classe python)
	TITLE="$$(echo "$(MODULE)" | awk -F_ '{for(i=1;i<=NF;i++){$$i=toupper(substr($$i,1,1)) substr($$i,2)}}1')"
	CLASS="$$(echo "$$TITLE" | tr -d ' ')"
	VERSION="$$( [ -n "$(ODOO_VERSION)" ] && echo "$(ODOO_VERSION)" || echo 17.0 ).1.0.0"
	# substitui os placeholders @X@ dos templates (bash puro — sem problemas de escaping)
	render() {
		local t="$$1"
		t="$${t//@MODULE@/$(MODULE)}"
		t="$${t//@TITLE@/$$TITLE}"
		t="$${t//@CLASS@/$$CLASS}"
		t="$${t//@AUTHOR@/$$AUTHOR}"
		t="$${t//@WEBSITE@/$$WEBSITE}"
		t="$${t//@CONTRIB@/$$CONTRIB_PY}"
		t="$${t//@VERSION@/$$VERSION}"
		printf '%s\n' "$$t"
	}
	mkdir -p "$$DIR/models" "$$DIR/views" "$$DIR/security"
	render "$$SCAFFOLD_MANIFEST" > "$$DIR/__manifest__.py"
	echo "from . import models" > "$$DIR/__init__.py"
	echo "from . import models" > "$$DIR/models/__init__.py"
	render "$$SCAFFOLD_MODELS" > "$$DIR/models/models.py"
	render "$$SCAFFOLD_VIEWS" > "$$DIR/views/views.xml"
	echo "id,name,model_id:id,group_id:id,perm_read,perm_write,perm_create,perm_unlink" > "$$DIR/security/ir.model.access.csv"
	render "$$SCAFFOLD_README" > "$$DIR/README.md"
	printf "$(C_GREEN)✓ módulo criado em addons/$(MODULE)$(C_RESET)\n"
	printf "$(C_DIM)  autor: $$AUTHOR · website: $$WEBSITE · versão: $$VERSION$(C_RESET)\n"
	printf "$(C_DIM)  próximo passo: make install MODULE=$(MODULE)$(C_RESET)\n"
