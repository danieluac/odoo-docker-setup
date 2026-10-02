# Ambiente Odoo em Docker

Ambiente de desenvolvimento Odoo completo (Odoo + PostgreSQL) gerido
inteiramente por `make`. **Não precisas de saber Docker**: subir o ambiente,
fazer backups, restaurar bases de dados, criar módulos, migrar de versão —
tudo é um único `make <comando>`.

Toda a configuração vive num único ficheiro, o **`.env`** (criado
automaticamente na primeira utilização). Aí ficam a versão do Odoo, as
portas, as credenciais e o resto.

**Uma branch por versão do Odoo**: `16.0`, `17.0`, `18.0`, `19.0` e `20.0`.
Clona a branch da versão que queres e o `.env` gerado já vem com essa versão.

---

## 1. Requisitos (uma única vez)

| Ferramenta | Onde obter |
|---|---|
| Docker (Desktop no Windows/macOS, Engine no Linux) com Compose v2 | https://docs.docker.com/get-docker/ |
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
git clone -b 20.0 <este-repo> odoo-20     # a branch = a versão do Odoo que queres
cd odoo-20
make up
```

Na primeira execução o `make up`:

1. cria o `.env` a partir do `.env.example` (podes editá-lo depois);
2. constrói a imagem do Odoo com as dependências do `requirements.txt`;
3. sobe o PostgreSQL e o Odoo;
4. inicializa a base de dados com os módulos base.

No fim aparece o endereço: **http://localhost:8069** — login `admin` / `admin`.

Para ver todos os comandos disponíveis:

```bash
make          # ou: make help
```

Se quiseres ajustar o `.env` **antes** do primeiro arranque (porta, versão do
PostgreSQL, credenciais…): `make init` cria-o sem subir nada; editas; depois
`make up`.

## 3. Versões do Odoo

Cada branch deste repositório corresponde a uma versão do Odoo e traz os
valores por omissão certos para ela. As diferenças entre branches resumem-se
a esses defaults — o `Makefile`, o `docker-compose.yml` e o `Dockerfile` são
os mesmos em todas.

| Branch / `ODOO_VERSION` | Imagem oficial `odoo:<v>` assenta em | Python | `POSTGRES_VERSION` por omissão | Estado da versão do Odoo |
|---|---|---|---|---|
| `16.0` | Debian 11 (bullseye) | 3.9 | 15 | fim de vida; imagem oficial sem actualizações desde set. 2025 |
| `17.0` | Ubuntu 22.04 (jammy) | 3.10 | 15 | fim de vida; imagem oficial sem actualizações desde set. 2026 |
| `18.0` | Ubuntu 24.04 (noble) | 3.12 | 16 | mantida |
| `19.0` | Ubuntu 24.04 (noble) | 3.12 | 17 | mantida |
| `20.0` | Ubuntu 24.04 (noble) | 3.12 | 17 | mantida (versão mais recente) |

A versão do PostgreSQL por omissão de cada branch cumpre o mínimo exigido
pela respectiva versão do Odoo. A imagem usada é `pgvector/pgvector:pg<v>`
(PostgreSQL oficial + extensão `vector`, útil para funcionalidades de IA).

O build da imagem termina sempre com uma **verificação de importação**
(Odoo, `cryptography`/`pyOpenSSL`/`urllib3`, `psycopg2`, `lxml`, `pandas`,
`pyodbc`, `debugpy`…): se alguma dependência tiver ficado inconsistente, o
`make up` pára no build com o erro legível, em vez de o servidor falhar a
arrancar mais tarde. A última linha do build mostra `OK: Odoo <versão> |
Python <versão>`.

### Notas por versão

**16.0** — A imagem oficial assenta em Debian 11, cujo suporte terminou em
Agosto de 2026, e os seus pacotes já não estão nos repositórios correntes do
Debian. O `Dockerfile` trata disso sozinho: ao detectar Debian 11, fixa as
fontes `apt` num snapshot datado do arquivo histórico do Debian
(`snapshot.debian.org`). Não precisas de configurar nada; conta apenas com
um primeiro build um pouco mais lento, porque esse serviço limita o débito.
Se quiseres outra data de snapshot, define `DEBIAN_SNAPSHOT` no `.env`. As
dependências Python do Odoo 16 que ficaram incompatíveis com bibliotecas
recentes (`pyOpenSSL`, `urllib3`) são também fixadas automaticamente.

**17.0** — Imagem baseada em Ubuntu 22.04. A Odoo deixou de a actualizar em
Setembro de 2026 (fim de vida da versão); continua a funcionar normalmente.

**18.0, 19.0, 20.0** — Imagens baseadas em Ubuntu 24.04, mantidas pela Odoo.
Nada de especial a configurar.

### Mudar de versão no mesmo clone

Também podes alterar `ODOO_VERSION` no `.env` de um clone e correr `make up`:
é criado um ambiente **novo e isolado** (containers, volumes, bases de dados
e filestore próprios) para essa versão, sem tocar no anterior. Voltar atrás
é repor o valor e correr `make up` outra vez. Para trabalho continuado numa
versão, a branch respectiva é a referência.

## 4. Portas

| Variável (`.env`) | Por omissão | Para quê |
|---|---|---|
| `ODOO_PORT` | `8069` | Interface web do Odoo → http://localhost:`ODOO_PORT`. É a única porta publicada no arranque normal (`make up`). |
| `ODOO_DEBUG_PORT` | `5678` | Depurador Python (debugpy). Só é publicada pelo `make debug`; o `make up` não a abre. |
| `POSTGRES_PORT` | vazio | Acesso ao PostgreSQL a partir do host (DBeaver, pgAdmin, `psql` local…). Vazio = **não publicado** — o Odoo fala com a base de dados pela rede interna do Docker, e tu usas `make psql`. Define p.ex. `POSTGRES_PORT=5432` para publicar; depois `make up`. |

Dentro da rede Docker o PostgreSQL está sempre em `db:5432`; essas portas só
dizem respeito ao que fica acessível na tua máquina. Se tiveres mais do que
um ambiente a correr (§8), cada um precisa dos seus valores.

## 5. Backups

```bash
make backup                          # BD activa, COM filestore (anexos/imagens)
make backup FILESTORE=0              # só a base de dados, sem filestore
make backup DB=outra_bd              # backup de outra BD
make backup-list                     # lista os backups existentes
```

Os backups ficam em `backups/` (configurável via `BACKUP_DIR` no `.env`) com
o nome `<bd>_<data>_<hora>.zip`, no **formato zip padrão do Odoo**
(`dump.sql` + `manifest.json` + `filestore/`). Por isso também podem ser
restaurados pela interface web do Odoo (gestor de bases de dados), e os
backups feitos pela interface web do Odoo (ou vindos de um servidor de
produção) podem ser restaurados aqui.

## 6. Restaurar uma base de dados

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
> `make update MODULE=all`. Se vier de **outra versão major** do Odoo, ver §9.

## 7. Dia-a-dia

```bash
make up          # sobe (ou actualiza) o ambiente
make down        # pára tudo — os dados persistem
make restart     # reinicia o servidor Odoo (aplica mudanças do .env)
make status      # versão, projecto, BD activa, portas, estado dos containers
make logs        # logs do Odoo em directo (Ctrl-C para sair)
make logs-db     # logs do PostgreSQL
```

### Bases de dados

```bash
make db-list             # lista as BDs deste ambiente
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

Cria a estrutura completa em `addons/minha_app/` (`__manifest__.py`,
`models/`, `views/`, `security/`, `README.md`), com o manifesto já
preenchido com o **autor**, o **website** e os **contribuidores** definidos
no `.env`:

```ini
MODULE_AUTHOR=A Minha Empresa
MODULE_WEBSITE=https://www.example.com
MODULE_CONTRIBUTORS=Ana Silva, Rui Costa
```

A versão do manifesto segue a versão do ambiente (ex.: `20.0.1.0.0`). Para
criar o módulo noutra pasta de addons (ver a secção seguinte), usa
`IN=<pasta>`, por exemplo `make scaffold MODULE=x IN=repos/seguros/addons`.

Módulos existentes: coloca-os numa pasta de addons e:

```bash
make install MODULE=meu_modulo     # instala (aceita vários: a,b,c)
make update MODULE=meu_modulo      # actualiza após mudares o código
make shell                         # consola python do Odoo (odoo shell)
```

Com `ODOO_DEV=reload,qweb,xml` (o default do `.env`), o servidor reinicia
sozinho quando um `.py` muda — na maioria dos casos nem precisas do
`make restart`.

### Módulos de outros repositórios

Os teus módulos vivem normalmente nos seus próprios repositórios git, com a
estrutura de pastas que tiverem. Há duas formas de os usar sem alterar
nenhum ficheiro deste setup — assim o `git pull` do setup nunca conflitua
com nada teu:

**1. A pasta `repos/` (sem configuração).** É ignorada pelo git deste setup.
Clona lá os repositórios de módulos, com qualquer estrutura interna:

```
repos/
├── seguros/            ← git clone do repo "seguros"
│   └── addons/extra-addons/seguros/   (pasta com módulos)
└── odoo_global/        ← git clone do repo "odoo_global"
    └── addons/custom-addons/          (pasta com módulos)
```

O `make up` (ou `make restart`) descobre automaticamente todas as pastas que
contêm módulos (pastas com `__manifest__.py` lá dentro) e põe-nas no
`addons_path`. Abre o setup como raiz do editor: o VS Code detecta cada
repositório dentro de `repos/` e mostra-os todos no painel *Source Control*
(configuração incluída em `.vscode/settings.json`).

**2. `ADDONS_PATHS` no `.env` (pastas fora do setup).** Para pastas de addons
noutro sítio do disco, lista-as separadas por vírgula (absolutas, `~/…` ou
relativas à raiz do setup), pela ordem de prioridade que o Odoo deve usar:

```ini
ADDONS_PATHS=../seguros/addons/extra-addons/seguros,../odoo_global/addons/custom-addons
```

Cada pasta é montada no container em `/mnt/addons/<nome-da-pasta>`. Se a
pasta não existir, o `make up` pára com um erro claro em vez de arrancar
sem os módulos.

Em ambos os casos o `addons_path` final fica, por esta ordem: Enterprise (se
definido), `addons/`, pastas em `repos/` (ordem alfabética), `ADDONS_PATHS`
(ordem do `.env`). O `make status` lista as pastas em uso e o mapeamento
host → container. O `make install`, `make update`, `make migrate-module` e o
debug funcionam em todas elas.

**Dependências Python dos módulos.** Se um repositório de módulos tiver um
`requirements.txt` (na raiz do repo ou junto dos módulos), as suas
dependências são instaladas **na imagem**: o `make up` junta todos os
`requirements.txt` que encontra em `addons/`, `repos/` e nas pastas de
`ADDONS_PATHS` (e nas pastas-mãe destas até à raiz do repo git) no ficheiro
gerado `config/requirements.addons.txt`, e o build instala-o numa camada
própria. Sempre que um desses ficheiros muda, o `make up` seguinte
reconstrói só essa camada. O `make status` lista os ficheiros encontrados.
Pacotes só declarados em `external_dependencies` do manifesto não são
instalados automaticamente — acrescenta-os a um `requirements.txt` do repo.

### Depuração (VS Code)

```bash
make debug      # sobe o Odoo sob debugpy, à escuta em ODOO_DEBUG_PORT (5678)
```

Depois, no VS Code: `F5` com a configuração **"Odoo"**. O ficheiro
`.vscode/launch.json` é gerado pelo `make up`/`make conf` com um
mapeamento por pasta de addons (`addons/`, `repos/` e `ADDONS_PATHS`), por
isso os breakpoints funcionam em todos os módulos. Em modo debug o
auto-reload fica desligado; `make up` volta ao modo normal. Para depurar o
próprio arranque do servidor, activa `ODOO_WAIT=1` no `.env`.

### Odoo Enterprise (opcional)

Se tiveres os addons Enterprise **da mesma versão** no disco, aponta o `.env`
para eles e corre `make up`:

```ini
ENTERPRISE_DIR=../enterprise-20.0
```

Vazio = modo Community.

## 8. Vários ambientes em simultâneo

Cada ambiente é um **projecto Docker** chamado `odoo-<versão>[-<INSTANCE>]`,
com containers, volumes e bases de dados próprios. Para ter dois a correr ao
mesmo tempo (dois clientes, ou duas versões), usa **dois clones** (duas
pastas), cada um com o seu `.env`:

| | Clone A (`.env`) | Clone B (`.env`) |
|---|---|---|
| Porta HTTP | `ODOO_PORT=8069` | `ODOO_PORT=8070` — tem de ser diferente |
| Mesma versão do Odoo? | `INSTANCE=cliente-a` | `INSTANCE=cliente-b` — obrigatório quando a versão é igual |
| Versões diferentes? | branch `16.0` | branch `18.0` — aqui o `INSTANCE` é opcional |
| Depurar os dois ao mesmo tempo? | `ODOO_DEBUG_PORT=5678` | `ODOO_DEBUG_PORT=5679` |
| PostgreSQL publicado nos dois? | `POSTGRES_PORT=5432` | `POSTGRES_PORT=5433` |

O `INSTANCE` dá a cada clone o seu próprio projecto Docker; o `make up`
confirma que o projecto pertence à pasta actual antes de avançar e, se não
pertencer, diz o que definir. `make status` mostra o projecto e a pasta a
que pertence. Os dados são isolados por projecto: o backup/restore de um
ambiente nunca toca no outro.

## 9. Migrar de versão (ex.: 16 → 17 → 18)

O que o Odoo permite e o que não permite:

| O quê | É possível? | Como |
|---|---|---|
| Migrar a **base de dados** (Community) | Sim, uma versão de cada vez | `make migrate` (OpenUpgrade, da OCA) |
| Migrar a **base de dados** com módulos Enterprise | Sim, só via Odoo | `make migrate-odoo` (serviço oficial, requer contrato Enterprise) |
| Migrar o **código dos módulos custom** | Em parte — a parte mecânica | `make migrate-module` (odoo-module-migrator, da OCA) + revisão manual |
| Voltar atrás (downgrade) | Não | usa o backup que o `make migrate` deixa antes de cada passo |

O Odoo Community não migra bases de dados entre versões sozinho — o
OpenUpgrade é a solução open-source da comunidade e funciona passo a passo
(16→17→18); o `make migrate` encadeia os passos por ti.

### 9.1 Migrar o código dos módulos custom (fazer PRIMEIRO)

```bash
make migrate-module MODULE=minha_app TO=18.0          # da versão do .env para a 18.0
make migrate-module MODULE=minha_app FROM=16.0 TO=17.0
```

Corre o `odoo-module-migrator` sobre o módulo **no lugar**, em qualquer das
pastas de addons (`addons/`, `repos/` ou `ADDONS_PATHS`) — faz commit antes. Trata do que é mecânico: versão no manifesto, ficheiros
renomeados e substituições conhecidas de cada versão. O que fica para ti está
no log em `migrations/` e no diff — tipicamente:

- **17.0**: `attrs="..."` e `states="..."` nas vistas passam a expressões
  (`invisible="state != 'draft'"`); `name_get()` → `_compute_display_name`
- **18.0**: `<tree>` → `<list>` nas vistas; vários métodos e assets renomeados
- JavaScript/Owl: quase sempre à mão

Testa cada módulo migrado na versão de destino antes de migrar a BD (no
clone da branch de destino: `make up` → `make install MODULE=minha_app`).

### 9.2 Migrar a base de dados

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
> - Os módulos custom instalados na BD **têm de existir já migrados** numa
>   pasta de addons para a versão de destino — senão o `-u all` falha (ou
>   deixa-os de fora). Alternativa: desinstalá-los antes de migrar.
> - O OpenUpgrade só cobre módulos Community (e nem todos os da OCA). Não
>   migra módulos Enterprise — para esses só o serviço oficial.
> - Funciona a partir da 14.0 (quando o OpenUpgrade passou a scripts sobre o
>   Odoo oficial).
> - Migração é trabalho sério: faz sempre um ensaio numa cópia, verifica os
>   dados na versão nova e só depois migra a BD real.

### 9.3 Serviço oficial da Odoo (Enterprise)

```bash
make migrate-odoo DB=prod TO=17.0                 # ensaio (MODE=test)
make migrate-odoo DB=prod TO=17.0 MODE=production
```

Corre o script oficial de `upgrade.odoo.com` dentro do container: a BD é
enviada à Odoo, migrada nos servidores deles e devolvida para o mesmo
PostgreSQL. Requer subscrição Enterprise válida; segue as mensagens do
script. Para usar a BD devolvida na versão nova: `make backup DB=<nome
devolvido>` e depois, no ambiente da versão nova, `make restore FILE=…`.

## 10. Variáveis do `.env`

| Variável | Por omissão | Descrição |
|---|---|---|
| `ODOO_VERSION` | a versão da branch | Versão do Odoo (`16.0` … `20.0`); cada versão = ambiente isolado |
| `POSTGRES_VERSION` | a da branch (§3) | Versão do PostgreSQL. Não mudar depois de já teres dados nesse ambiente |
| `ODOO_PORT` | `8069` | Porta HTTP → http://localhost:`porta` |
| `ODOO_DEBUG_PORT` | `5678` | Porta do debugpy (publicada só pelo `make debug`) |
| `POSTGRES_PORT` | vazio | Porta do PostgreSQL no host (vazio = não publicado) |
| `INSTANCE` | vazio | Identificador do ambiente; obrigatório para dois clones da mesma versão (§8) |
| `ODOO_DB` | `odoo` | BD activa (actualizada pelo `make restore`/`db-use`) |
| `POSTGRES_USER` / `POSTGRES_PASSWORD` | `odoo`/`odoo` | Credenciais do PostgreSQL |
| `ADMIN_PASSWD` | `admin` | Master password do gestor de BDs do Odoo |
| `ODOO_LOG` | `info` | Nível de log (`debug`, `info`, `warn`, `error`) |
| `ODOO_DEV` | `reload,qweb,xml` | Modos dev do Odoo (`none` desactiva) |
| `ODOO_DEBUG` / `ODOO_WAIT` | — | Debug permanente / esperar pelo VS Code antes de arrancar |
| `ENTERPRISE_DIR` | vazio | Caminho dos addons Enterprise (vazio = Community) |
| `ADDONS_PATHS` | vazio | Pastas de addons fora do setup, separadas por vírgula (§7); alternativa sem configuração: pasta `repos/` |
| `BACKUP_DIR` | `./backups` | Pasta dos backups |
| `MODULE_AUTHOR` / `MODULE_WEBSITE` / `MODULE_CONTRIBUTORS` | genéricos | Identidade usada no manifesto do `make scaffold` |
| `PG_TUNING` | `1` | PostgreSQL afinado para desenvolvimento (restores rápidos; nunca em produção) |
| `DEBIAN_SNAPSHOT` | `20260901T000000Z` | Só Odoo 16: data do snapshot Debian usado no build (§3) |

O `.env` nunca é regenerado — é teu. A precedência é simples: **tudo vem do
`.env`**; os únicos "parâmetros" de linha de comando são os argumentos por
operação (`DB=`, `FILE=`, `MODULE=`, `FILESTORE=`, `NEUTRALIZE=`, `TO=`…).

## 11. Perguntas frequentes

**"port is already allocated" ao subir** — outra aplicação (ou outro
ambiente deste setup) usa a porta. Muda `ODOO_PORT` (ou `POSTGRES_PORT` /
`ODOO_DEBUG_PORT`, conforme o caso) no `.env` e corre `make up`.

**"o Docker não está a correr"** — abre o Docker Desktop (Windows/macOS)
ou `sudo systemctl start docker` (Linux).

**Esqueci-me dos comandos** — `make` (sem argumentos) mostra sempre a ajuda.

**Quero começar do zero** — `make destroy` apaga containers, volumes e
todas as BDs **deste ambiente** (pede confirmação; outros ambientes e a
pasta `backups/` não são tocados).

**Restaurei uma BD e o Odoo dá erros de módulos** — o backup vem de outro
código: `make update MODULE=all`. Se vem de outra versão major: §9.

**O primeiro build do Odoo 16 é lento ou falha a descarregar pacotes** —
os pacotes vêm do arquivo histórico do Debian, que limita o débito. Repete o
`make up` (as camadas já construídas ficam em cache); se persistir,
experimenta outra data em `DEBIAN_SNAPSHOT` no `.env`.

**Quero ligar o DBeaver/pgAdmin à base de dados** — define `POSTGRES_PORT`
no `.env` (§4) e corre `make up`; liga a `localhost:<porta>` com as
credenciais `POSTGRES_USER`/`POSTGRES_PASSWORD`.

## 12. Notas de segurança

Este setup é para **desenvolvimento**: credenciais por omissão fracas,
tuning do PostgreSQL sem durabilidade em crash (`PG_TUNING=1`) e
`list_db = True`. Se o ambiente ficar acessível fora da tua máquina, muda as
credenciais no `.env` e não publiques `POSTGRES_PORT` — e nunca uses este
compose em produção.
