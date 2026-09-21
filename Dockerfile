# Imagem Odoo do ambiente: oficial + dependências do requirements.txt.
# A versão vem do .env (ODOO_VERSION) via build arg — passado pelo compose.
ARG ODOO_VERSION=17.0
FROM odoo:${ODOO_VERSION}

USER root

# toolchain para compilar wheels (pyodbc precisa de unixodbc-dev, etc.);
# git: necessário para instalar a openupgradelib e para o make migrate-module
RUN apt-get update \
    && apt-get install -y --no-install-recommends build-essential python3-dev unixodbc-dev git \
    && rm -rf /var/lib/apt/lists/*

COPY requirements.txt /tmp/requirements.txt

# PIP_BREAK_SYSTEM_PACKAGES: necessário nas imagens Debian bookworm+ (PEP 668);
# ignorado silenciosamente pelo pip antigo das imagens mais velhas.
ENV PIP_BREAK_SYSTEM_PACKAGES=1

# deps instaladas com uv (rápido e resolução previsível);
# watchdog: necessário para o auto-reload (--dev=reload);
# openupgradelib (master, como a OCA recomenda): necessária ao make migrate (OpenUpgrade)
RUN pip3 install --no-cache-dir uv \
    && uv pip install --system --break-system-packages --no-cache \
        -r /tmp/requirements.txt watchdog \
        "openupgradelib @ git+https://github.com/OCA/openupgradelib.git@master"

# Odoo 16: o requirements arrasta cryptography recente → o pyOpenSSL e o
# urllib3 da imagem ficam incompatíveis; urllib3<2 porque o Odoo 16 importa
# urllib3.contrib.pyopenssl (removido na 2.x). Só se aplica ao 16.
ARG ODOO_VERSION
RUN if [ "${ODOO_VERSION%%.*}" = "16" ]; then \
        uv pip install --system --break-system-packages --no-cache \
            "pyOpenSSL>=23.2" "urllib3>=1.26.16,<2"; \
    fi

USER odoo
