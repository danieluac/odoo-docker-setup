# Imagem Odoo do ambiente: oficial + dependências do requirements.txt.
# A versão vem do .env (ODOO_VERSION) via build arg — passado pelo compose.
ARG ODOO_VERSION=17.0
FROM odoo:${ODOO_VERSION}

USER root

# toolchain para compilar wheels (pyodbc precisa de unixodbc-dev, etc.)
#
# Debian 11 "bullseye" — base da imagem odoo:16 — saiu do suporte LTS em
# 2026-08-31. A partir daí o apt da imagem parte: os índices ainda respondem
# mas os .deb (sobretudo em bullseye-security) já foram apagados do pool
# (404), e o archive.debian.org pode ainda não ter a release publicada.
# Solução: em bullseye, fixar as fontes num snapshot datado do
# snapshot.debian.org (tem tudo, congelado). Como os ficheiros Release do
# snapshot já expiraram, desliga-se a validação de data; os retries ajudam
# com o rate-limit do snapshot. Bookworm+ (Odoo 17/18) não é tocado.
# Override pontual: docker compose build --build-arg DEBIAN_SNAPSHOT=…
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
    apt-get install -y --no-install-recommends build-essential python3-dev unixodbc-dev; \
    rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

# PIP_BREAK_SYSTEM_PACKAGES: necessário nas imagens Debian bookworm+ (PEP 668);
# ignorado silenciosamente pelo pip antigo das imagens mais velhas.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# deps instaladas com uv (rápido e resolução previsível);
# watchdog: necessário para o auto-reload (--dev=reload)
RUN pip3 install --no-cache-dir uv \
    && uv pip install --system --break-system-packages --no-cache \
        -r /tmp/requirements.txt watchdog

# Odoo 16: o requirements arrasta cryptography recente → o pyOpenSSL e o
# urllib3 da imagem ficam incompatíveis; urllib3<2 porque o Odoo 16 importa
# urllib3.contrib.pyopenssl (removido na 2.x). Só se aplica ao 16.
ARG ODOO_VERSION
RUN if [ "${ODOO_VERSION%%.*}" = "16" ]; then \
        uv pip install --system --break-system-packages --no-cache \
            "pyOpenSSL>=23.2" "urllib3>=1.26.16,<2"; \
    fi

USER odoo
