# Ambiente Odoo em Docker

Ambiente de desenvolvimento Odoo completo (Odoo + Postgres) gerido inteiramente
por `make`. **Não precisas de saber Docker** — todos os comandos do dia-a-dia
(subir o ambiente, backups, restores, gestão de bases de dados) são um único
`make <comando>`.

Toda a configuração vive num único ficheiro: o **`.env`** (criado
automaticamente na primeira utilização). Aí escolhes a **versão do Odoo**,
a porta, as credenciais, etc.

---

## 1. Requisitos (uma única vez)

| Ferramenta | Onde obter |
|---|---|
| Docker (Desktop no Windows/macOS, Engine no Linux) | https://docs.docker.com/get-docker/ |
| `make` | já vem no macOS/Linux; no Windows usa WSL2 |
| `git` | https://git-scm.com |

> No Windows, trabalha sempre dentro do WSL2 (Ubuntu). O Docker Desktop
> integra-se com o WSL2 automaticamente.

## 2. Começar

```bash
git clone <este-repo>
cd odoo-docker-setup
make up
```

Na primeira execução o `make up`:

1. cria o `.env` a partir do `.env.example` (podes editá-lo depois);
2. constrói a imagem do Odoo com as dependências do `requirements.txt`;
3. sobe o Postgres e o Odoo;
4. inicializa a base de dados com os módulos base.

No fim aparece o endereço: **http://localhost:8069** — login `admin` / `admin`.

Para veres todos os comandos disponíveis:

```bash
make          # ou: make help
```

## 3. Escolher a versão do Odoo

Edita o `.env` e muda a linha:

```ini
ODOO_VERSION=16.0     # → 17.0, 18.0, …
```

Depois corre `make up`. **Cada versão tem um ambiente completamente
isolado** (containers, volumes, bases de dados e filestore próprios):
mudar de versão não apaga nada — voltar atrás é repor o valor antigo e
correr `make up` outra vez.

## 4. Backups

```bash
make backup                          # BD activa, COM filestore (anexos/imagens)
make backup FILESTORE=0              # só a base de dados, sem filestore
make backup DB=outra_bd              # backup de outra BD
make backup-list                     # lista os backups existentes
```

Os backups ficam em `backups/` (configurável via `BACKUP_DIR` no `.env`) com
o nome `<bd>_<data>_<hora>.zip`, no **formato zip padrão do Odoo**
(`dump.sql` + `manifest.json` + `filestore/`) — por isso também podem ser
restaurados pela interface web do Odoo (gestor de bases de dados), e os
backups feitos pela interface web do Odoo (ou de um servidor de produção)
podem ser restaurados aqui.

## 5. Restaurar uma base de dados

```bash
make restore FILE=backups/producao.zip            # cria/substitui a BD "producao"
make restore FILE=backups/producao.zip DB=teste   # restaura com outro nome
make restore FILE=dump.sql DB=minha_bd            # também aceita .sql e .dump
```

O que acontece automaticamente:

- a BD é (re)criada e o `dump.sql` é importado em **streaming** (dumps de
  produção com muitos GB nunca passam por ficheiros temporários);
- o **filestore** é reposto, se existir no zip;
- a BD é **neutralizada** para desenvolvimento — crons e servidores de
  email ficam desligados, para o ambiente não enviar emails reais nem
  correr tarefas agendadas de produção (`NEUTRALIZE=0` evita);
- a BD restaurada passa a ser a **BD activa** (o `.env` é actualizado).

> Se o backup vier de um código/versão diferente, alinha o schema com:
> `make update MODULE=all`

## 6. Dia-a-dia

```bash
make up          # sobe (ou actualiza) o ambiente
make down        # pára tudo — os dados persistem
make restart     # reinicia o servidor Odoo (aplica mudanças do .env)
make status      # versão, BD activa, estado dos containers
make logs        # logs do Odoo em directo (Ctrl-C para sair)
make logs-db     # logs do Postgres
```

### Bases de dados

```bash
make db-list             # lista as BDs desta versão
make db-use DB=teste     # muda a BD activa (sem restaurar nada)
make db-drop DB=teste    # apaga uma BD + filestore (pede confirmação)
make psql                # terminal SQL na BD activa
make neutralize DB=x     # desliga crons/email numa BD (cópias de produção)
```

### Módulos custom

Para criar um módulo novo do zero:

```bash
make scaffold MODULE=minha_app
```

Isto cria a estrutura completa em `addons/minha_app/` (`__manifest__.py`,
`models/`, `views/`, `security/`, `README.md`), com o manifesto já
preenchido com o **autor**, o **website** e os **contribuidores** definidos
no `.env`:

```ini
MODULE_AUTHOR=A Minha Empresa
MODULE_WEBSITE=https://www.example.com
MODULE_CONTRIBUTORS=Ana Silva, Rui Costa
```

A versão do manifesto segue a versão do ambiente (ex.: `17.0.1.0.0`). Se
estas chaves não existirem no teu `.env` (criado por uma versão anterior do
setup), são acrescentadas automaticamente com valores por omissão.

Módulos existentes: coloca-os na pasta `addons/` e:

```bash
make install MODULE=meu_modulo     # instala (aceita vários: a,b,c)
make update MODULE=meu_modulo      # actualiza após mudares o código
make shell                         # consola python do Odoo (odoo shell)
```

Com `ODOO_DEV=reload,qweb,xml` (o default do `.env`), o servidor reinicia
sozinho quando um `.py` muda — na maioria dos casos nem precisas do
`make restart`.

### Debug (VS Code)

```bash
make debug      # sobe o Odoo sob debugpy, à escuta na porta 5678
```

Depois, no VS Code: `F5` com a configuração **"Odoo"** (já incluída em
`.vscode/launch.json`). Breakpoints nos módulos em `addons/` funcionam
directamente. `make up` volta ao modo normal. Para debugar o próprio
arranque do servidor, activa `ODOO_WAIT=1` no `.env`.

### Odoo Enterprise (opcional)

Se tiveres os addons Enterprise no disco, aponta o `.env` para eles:

```ini
ENTERPRISE_DIR=../enterprise-17.0
```

e corre `make up`. Vazio = modo Community.

## 7. Migrar de versão (ex.: 16 → 17 → 18)

Primeiro, o que o Odoo permite e o que não permite — para não haver surpresas:

| O quê | É possível? | Como |
|---|---|---|
| Migrar a **base de dados** (Community) | Sim, uma versão de cada vez | `make migrate` (OpenUpgrade, da OCA) |
| Migrar a **base de dados** com módulos Enterprise | Sim, só via Odoo | `make migrate-odoo` (serviço oficial, requer contrato Enterprise) |
| Migrar o **código dos módulos custom** | Em parte — a parte mecânica | `make migrate-module` (odoo-module-migrator, da OCA) + revisão manual |
| Voltar atrás (downgrade) | Não | usa o backup que o `make migrate` deixa antes de cada passo |

O Odoo Community **não migra bases de dados entre versões sozinho** — o
OpenUpgrade é a solução open-source da comunidade e funciona passo a passo
(16→17→18); o `make migrate` encadeia os passos por ti.

### 7.1 Migrar o código dos módulos custom (fazer PRIMEIRO)

```bash
make migrate-module MODULE=minha_app TO=18.0          # da versão do .env para a 18.0
make migrate-module MODULE=minha_app FROM=16.0 TO=17.0
```

Corre o `odoo-module-migrator` sobre `addons/minha_app` **no lugar** (faz
commit antes!). Ele trata do que é mecânico: versão no manifesto, ficheiros
renomeados e substituições conhecidas de cada versão. O que fica para ti está
no log em `migrations/` e no diff — tipicamente:

- **17.0**: `attrs="..."` e `states="..."` nas vistas passam a expressões
  (`invisible="state != 'draft'"`); `name_get()` → `_compute_display_name`
- **18.0**: `<tree>` → `<list>` nas vistas; vários métodos e assets renomeados
- JavaScript/Owl: quase sempre à mão

Testa cada módulo migrado na versão de destino antes de migrar a BD:
`ODOO_VERSION=18.0` no `.env` → `make up` → `make install MODULE=minha_app`.

### 7.2 Migrar a base de dados

```bash
make migrate DB=prod TO=17.0             # da versão do .env (ex.: 16.0) para a 17.0
make migrate DB=prod TO=18.0             # encadeia: 16.0 → 17.0 → 18.0
make migrate DB=prod TO=18.0 SWITCH=1    # …e no fim muda o .env e sobe o ambiente 18.0
```

Para cada passo, o `make migrate`:

1. faz um backup da BD na versão actual (`backups/prod_antes-de-17.0.zip` —
   o teu ponto de retorno);
2. obtém o OpenUpgrade dessa versão (`migrations/openupgrade-17.0/`);
3. restaura a BD no ambiente isolado da versão seguinte;
4. corre `odoo -u all` com os scripts de migração (log em `migrations/`).

A BD original na versão antiga **fica intacta** — a migrada vive no ambiente
da versão nova. Sem `SWITCH=1`, no fim dizes tu quando mudar:
`ODOO_VERSION=17.0` e `ODOO_DB=prod` no `.env` → `make up`.

> **Requisitos e limites**
> - Os módulos custom instalados na BD **têm de existir já migrados** em
>   `addons/` para a versão de destino — senão o `-u all` falha (ou deixa-os
>   de fora). Alternativa: desinstalá-los antes de migrar.
> - O OpenUpgrade só cobre módulos Community (e nem todos os da OCA). Não
>   migra módulos Enterprise — para esses só o serviço oficial.
> - Funciona a partir da 14.0 (quando o OpenUpgrade passou a scripts sobre o
>   Odoo oficial).
> - Migração é trabalho sério: faz sempre um ensaio numa cópia, verifica os
>   dados na versão nova e só depois migra a BD real.

### 7.3 Serviço oficial da Odoo (Enterprise)

```bash
make migrate-odoo DB=prod TO=17.0                 # ensaio (MODE=test)
make migrate-odoo DB=prod TO=17.0 MODE=production
```

Corre o script oficial de `upgrade.odoo.com` dentro do container: a BD é
enviada à Odoo, migrada nos servidores deles e devolvida para o mesmo
Postgres. Requer subscrição Enterprise válida; segue as mensagens do script.
Para usar a BD devolvida na versão nova: `make backup DB=<nome devolvido>` e
depois, com `ODOO_VERSION` da versão nova no `.env`, `make restore FILE=…`.

## 8. Variáveis do `.env`

| Variável | Default | Descrição |
|---|---|---|
| `ODOO_VERSION` | `16.0` | Versão do Odoo (cada versão = ambiente isolado) |
| `POSTGRES_VERSION` | `15` | Versão do Postgres (não mudar com dados existentes) |
| `ODOO_PORT` | `8069` | Porta HTTP → http://localhost:`porta` |
| `ODOO_DB` | `odoo` | BD activa (gerida pelo `make restore`/`db-use`) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | `odoo`/`odoo` | Credenciais do Postgres |
| `ADMIN_PASSWD` | `admin` | Master password do gestor de BDs do Odoo |
| `ODOO_LOG` | `info` | Nível de log (`debug`, `info`, `warn`, `error`) |
| `ODOO_DEV` | `reload,qweb,xml` | Modos dev do Odoo (`none` desactiva) |
| `ODOO_DEBUG_PORT` | `5678` | Porta do debugpy (`make debug`) |
| `ODOO_DEBUG` / `ODOO_WAIT` | — | Debug permanente / esperar pelo VS Code |
| `ENTERPRISE_DIR` | vazio | Caminho dos addons Enterprise (vazio = Community) |
| `BACKUP_DIR` | `./backups` | Pasta dos backups |
| `MODULE_AUTHOR` / `MODULE_WEBSITE` / `MODULE_CONTRIBUTORS` | genéricos | Identidade usada no manifesto do `make scaffold` |
| `PG_TUNING` | `1` | Postgres afinado p/ dev (restores rápidos; nunca em produção) |

O `.env` nunca é regenerado — é teu. A precedência é simples: **tudo vem do
`.env`**; os únicos "parâmetros" de linha de comando são os argumentos por
operação (`DB=`, `FILE=`, `MODULE=`, `FILESTORE=`, `NEUTRALIZE=`).

## 9. Problemas comuns

**"porta already in use" ao subir** — outra aplicação usa a porta 8069.
Muda `ODOO_PORT` no `.env` e corre `make up`.

**"o Docker não está a correr"** — abre o Docker Desktop (Windows/macOS)
ou `sudo systemctl start docker` (Linux).

**Esqueci-me dos comandos** — `make` (sem argumentos) mostra sempre a ajuda.

**Quero começar do zero** — `make destroy` apaga containers, volumes e
todas as BDs **da versão actual** (pede confirmação; as outras versões e a
pasta `backups/` não são tocadas).

**Restaurei uma BD e o Odoo dá erros de módulos** — o backup vem de outro
código/versão: `make update MODULE=all`.

**Odoo 16: o build falha no `apt-get` com 404 / "Release file expired"** —
a imagem `odoo:16` assenta em Debian 11 (bullseye), que saiu do suporte em
Agosto de 2026; os pacotes deixaram de estar nos mirrors normais. O
`Dockerfile` detecta bullseye e fixa o apt num snapshot datado do
`snapshot.debian.org`, por isso o `make up` com `ODOO_VERSION=16.0` continua
a funcionar sem fazeres nada. Se o snapshot estiver lento ou a dar erro
(é um serviço com rate-limit), repete o `make up`; se persistir, experimenta
outra data no `.env` (`DEBIAN_SNAPSHOT=20260815T000000Z`) e volta a correr
`make up`. As versões 17/18 (bookworm) não são afectadas.

## 10. Notas de segurança

Este setup é para **desenvolvimento**: credenciais default fracas, tuning
do Postgres sem durabilidade em crash (`PG_TUNING=1`) e `list_db = True`.
Se o ambiente ficar acessível fora da tua máquina, muda as credenciais no
`.env` — e nunca uses este compose em produção.
