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
| `make` | nem sempre vem instalado — ver abaixo |
| `git` | https://git-scm.com |

> No Windows, trabalha sempre dentro do WSL2 (Ubuntu). O Docker Desktop
> integra-se com o WSL2 automaticamente.

### Instalar o `make`

Confirma primeiro se já o tens: `make --version`. Se não:

| Sistema | Comando |
|---|---|
| Ubuntu / Debian (e WSL2 no Windows) | `sudo apt update && sudo apt install -y make` |
| Fedora / RHEL / Rocky | `sudo dnf install -y make` |
| Arch / Manjaro | `sudo pacman -S make` |
| macOS | `xcode-select --install` (instala as Command Line Tools, que incluem o `make`) — ou `brew install make` |
| Windows | abre o terminal do **WSL2 (Ubuntu)** e usa a linha do Ubuntu acima; não uses um `make` nativo do Windows |

Depois de instalar, `make --version` deve mostrar "GNU Make 4.x" (ou 3.81 no
macOS com as Command Line Tools — também serve).

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

Coloca os teus módulos na pasta `addons/` e:

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
directamente. `make up` volta ao modo normal (e deixa de publicar a porta
do debugpy). Para debugar o próprio arranque do servidor, activa
`ODOO_WAIT=1` no `.env`.

### Odoo Enterprise (opcional)

Se tiveres os addons Enterprise no disco, aponta o `.env` para eles:

```ini
ENTERPRISE_DIR=../enterprise-17.0
```

e corre `make up`. Vazio = modo Community.

## 7. Vários ambientes em simultâneo

Cada ambiente é um **projecto Docker** chamado `odoo-<versão>[-<INSTANCE>]`,
com containers, volumes e bases de dados próprios. Para ter dois a correr ao
mesmo tempo (ex.: dois clientes, ou duas versões), usa **dois clones do repo**
(duas pastas), cada um com o seu `.env`:

| | Clone A (`.env`) | Clone B (`.env`) |
|---|---|---|
| Porta HTTP | `ODOO_PORT=8069` | `ODOO_PORT=8070` ← tem de ser diferente |
| Mesma versão do Odoo? | `INSTANCE=cliente-a` | `INSTANCE=cliente-b` ← obrigatório se a versão for igual |
| Versões diferentes? | `ODOO_VERSION=16.0` | `ODOO_VERSION=18.0` (aqui o `INSTANCE` é opcional) |
| Debug nos dois ao mesmo tempo? | `ODOO_DEBUG_PORT=5678` | `ODOO_DEBUG_PORT=5679` |

Porquê o `INSTANCE`: sem ele, dois clones com a mesma versão apontam para o
**mesmo** projecto Docker, e o `make up` de um recria os containers do outro
com a sua configuração — é o sintoma de "um dos ambientes morre". O `make up`
agora detecta essa situação e recusa-se a avançar com uma mensagem a explicar
o que definir.

`make status` mostra o nome do projecto e a pasta a que pertence. Os dados são
isolados por projecto: o backup/restore de um ambiente nunca toca no outro.

## 8. Variáveis do `.env`

| Variável | Default | Descrição |
|---|---|---|
| `ODOO_VERSION` | `16.0` | Versão do Odoo (cada versão = ambiente isolado) |
| `POSTGRES_VERSION` | `15` | Versão do Postgres (não mudar com dados existentes) |
| `ODOO_PORT` | `8069` | Porta HTTP → http://localhost:`porta` |
| `INSTANCE` | vazio | Identificador do ambiente; obrigatório para correr dois clones da mesma versão (§7) |
| `ODOO_DB` | `odoo` | BD activa (gerida pelo `make restore`/`db-use`) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | `odoo`/`odoo` | Credenciais do Postgres |
| `ADMIN_PASSWD` | `admin` | Master password do gestor de BDs do Odoo |
| `ODOO_LOG` | `info` | Nível de log (`debug`, `info`, `warn`, `error`) |
| `ODOO_DEV` | `reload,qweb,xml` | Modos dev do Odoo (`none` desactiva) |
| `ODOO_DEBUG_PORT` | `5678` | Porta do debugpy (`make debug`) |
| `ODOO_DEBUG` / `ODOO_WAIT` | — | Debug permanente / esperar pelo VS Code |
| `ENTERPRISE_DIR` | vazio | Caminho dos addons Enterprise (vazio = Community) |
| `BACKUP_DIR` | `./backups` | Pasta dos backups |
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
