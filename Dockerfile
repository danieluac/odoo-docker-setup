# Imagem Odoo do ambiente: oficial + dependências do requirements.txt.
# A versão vem do .env (ODOO_VERSION) via build arg — passado pelo compose.
ARG ODOO_VERSION=16.0
FROM odoo:${ODOO_VERSION}

USER root

# toolchain para compilar wheels (pyodbc precisa de unixodbc-dev, etc.);
# git: necessário para instalar a openupgradelib e para o make migrate-module
#
# Odoo 16: a imagem oficial assenta em Debian 11 "bullseye", cujo suporte
# terminou em 2026-08-31 — os seus pacotes já não estão nos repositórios
# correntes do Debian. Em bullseye, as fontes apt são por isso fixadas num
# snapshot datado do arquivo histórico (snapshot.debian.org). Os ficheiros
# Release desse arquivo já expiraram (daí Check-Valid-Until=false) e o
# serviço limita o débito (daí os retries). As imagens Ubuntu (Odoo 17+)
# não são tocadas. A data vem do .env (DEBIAN_SNAPSHOT) via build arg.
ARG DEBIAN_SNAPSHOT=20260901T000000Z
RUN set -eux; \
    if grep -q '^VERSION_CODENAME=bullseye' /etc/os-release; then \
        SNAP="http://snapshot.debian.org/archive"; \
        printf '%s\n' \
            "deb ${SNAP}/debian/${DEBIAN_SNAPSHOT} bullseye main" \
            "deb ${SNAP}/debian/${DEBIAN_SNAPSHOT} bullseye-updates main" \
            "deb ${SNAP}/debian-security/${DEBIAN_SNAPSHOT} bullseye-security main" \
            > /etc/apt/sources.list; \
        rm -f /etc/apt/sources.list.d/*.list /etc/apt/sources.list.d/*.sources; \
        printf '%s\n' \
            'Acquire::Check-Valid-Until "false";' \
            'Acquire::Retries "5";' \
            > /etc/apt/apt.conf.d/99-bullseye-snapshot; \
    fi; \
    apt-get update; \
    apt-get install -y --no-install-recommends build-essential python3-dev unixodbc-dev git; \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

# PIP_BREAK_SYSTEM_PACKAGES: necessário nas imagens Ubuntu 24.04 (Odoo 18+),
# cujo pip aplica a PEP 668; ignorado pelo pip mais antigo das outras imagens.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# deps instaladas com uv (rápido e resolução previsível);
# watchdog: necessário para o auto-reload (--dev=reload);
# openupgradelib (master, como a OCA recomenda): necessária ao make migrate (OpenUpgrade).
#
# Nota: o uv não considera os pacotes Python que a imagem oficial traz via
# apt (/usr/lib/python3/dist-packages) — qualquer dependência sem versão
# (ex.: o lxml exigido pela openupgradelib) é instalada de novo, na versão
# mais recente, em /usr/local, e passa a ser essa que o Odoo importa.
# lxml-html-clean: a partir do lxml 5.2 o módulo lxml.html.clean (usado pelo
# Odoo) vive neste pacote separado — é obrigatório em todas as versões.
RUN pip3 install --no-cache-dir uv \
    && uv pip install --system --break-system-packages --no-cache \
        -r /tmp/requirements.txt watchdog lxml-html-clean \
        "openupgradelib @ git+https://github.com/OCA/openupgradelib.git@master"

# Odoo 16: o requirements arrasta cryptography recente → o pyOpenSSL e o
# urllib3 da imagem ficam incompatíveis; urllib3<2 porque o Odoo 16 importa
# urllib3.contrib.pyopenssl (removido na 2.x); lxml<6 porque o Odoo 16 só
# está validado até ao lxml 5.x (com lxml-html-clean). Só se aplica ao 16.
ARG ODOO_VERSION
RUN if [ "${ODOO_VERSION%%.*}" = "16" ]; then \
        uv pip install --system --break-system-packages --no-cache \
            "pyOpenSSL>=23.2" "urllib3>=1.26.16,<2" "lxml>=5.2,<6"; \
    fi

# Verificação no fim do build: importa o Odoo e as bibliotecas sensíveis a
# versões (cryptography/pyOpenSSL/urllib3/lxml) e as dependências instaladas.
# Se alguma combinação tiver ficado inconsistente, o build falha AQUI com o
# erro de import, em vez de o servidor falhar a arrancar mais tarde.
RUN python3 -c "import importlib, sys; \
    [importlib.import_module(m) for m in 'OpenSSL cryptography urllib3 requests psycopg2 lxml lxml.html.clean pandas pyodbc debugpy watchdog odoo odoo.tools.mail odoo.release'.split()]; \
    import odoo.release as r; print('OK: Odoo', r.version, '| Python', sys.version.split()[0])"

USER odoo
