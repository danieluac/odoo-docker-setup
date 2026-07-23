#!/usr/bin/env python3
"""Utilitário interno de backup/restore — corre DENTRO do container Odoo.

Não usar directamente: é invocado pelo Makefile (make backup / make restore).

Comandos:
  zip <out.zip> <db> <filestore 0|1> <odoo_version> <pg_version>
      Cria um backup no formato zip do Odoo (dump.sql + manifest.json +
      filestore). O dump.sql é lido do stdin (pg_dump em streaming — nunca
      passa por ficheiros temporários). Se BACKUP_UID/BACKUP_GID estiverem
      no ambiente, o zip final fica com esse dono (o utilizador do host).
  cat <backup.zip> <membro>
      Envia um membro do zip para o stdout em streaming (p.ex. dump.sql
      directo para o psql, sem tocar no disco).
  check <backup.zip>
      Valida que o zip é um backup Odoo (contém dump.sql); sai com erro se não.
  has-filestore <backup.zip>
      Sai com 0 se o zip contém ficheiros de filestore, 1 caso contrário.
  extract-filestore <backup.zip> <db>
      Extrai o filestore do zip para /var/lib/odoo/filestore/<db>
      (substitui o existente) e entrega a posse ao utilizador odoo.
"""
import json
import os
import pwd
import shutil
import sys
import zipfile

FILESTORE_ROOT = "/var/lib/odoo/filestore"
CHUNK = 1024 * 1024


def _installed_modules(db):
    """Módulos instalados, para o manifest.json (best-effort)."""
    try:
        import psycopg2

        conn = psycopg2.connect(
            host=os.environ.get("HOST", "db"),
            user=os.environ.get("USER", "odoo"),
            password=os.environ.get("PASSWORD", ""),
            dbname=db,
        )
        try:
            with conn.cursor() as cur:
                cur.execute(
                    "SELECT name, COALESCE(latest_version, '') "
                    "FROM ir_module_module WHERE state = 'installed'"
                )
                return dict(cur.fetchall())
        finally:
            conn.close()
    except Exception as exc:
        print(f"aviso: manifest fica sem lista de módulos ({exc})", file=sys.stderr)
        return {}


def cmd_zip(out_path, db, with_filestore, odoo_version, pg_version):
    major = ".".join(odoo_version.split(".")[:2])
    manifest = {
        "odoo_dump": "1",
        "db_name": db,
        "version": major,
        "version_info": [int(odoo_version.split(".")[0]), 0, 0, "final", 0, ""],
        "major_version": major,
        "pg_version": pg_version,
        "modules": _installed_modules(db),
    }
    with zipfile.ZipFile(out_path, "w", zipfile.ZIP_DEFLATED, allowZip64=True) as zf:
        with zf.open("dump.sql", "w", force_zip64=True) as member:
            shutil.copyfileobj(sys.stdin.buffer, member, CHUNK)
        zf.writestr("manifest.json", json.dumps(manifest, indent=2))
        if with_filestore == "1":
            fs_dir = os.path.join(FILESTORE_ROOT, db)
            if os.path.isdir(fs_dir):
                for root, _dirs, files in os.walk(fs_dir):
                    for name in files:
                        full = os.path.join(root, name)
                        arc = os.path.join("filestore", os.path.relpath(full, fs_dir))
                        zf.write(full, arc)
            else:
                print(
                    f"aviso: sem filestore em {fs_dir} — o backup fica só com a BD",
                    file=sys.stderr,
                )
    uid = int(os.environ.get("BACKUP_UID", "-1"))
    gid = int(os.environ.get("BACKUP_GID", "-1"))
    if uid >= 0:
        os.chown(out_path, uid, gid)


def cmd_cat(zip_path, member):
    with zipfile.ZipFile(zip_path) as zf, zf.open(member) as src:
        shutil.copyfileobj(src, sys.stdout.buffer, CHUNK)


def cmd_check(zip_path):
    with zipfile.ZipFile(zip_path) as zf:
        if "dump.sql" not in zf.namelist():
            print(
                "✗ o zip não contém dump.sql — não é um backup Odoo válido",
                file=sys.stderr,
            )
            sys.exit(1)


def cmd_has_filestore(zip_path):
    with zipfile.ZipFile(zip_path) as zf:
        has = any(
            n.startswith("filestore/") and not n.endswith("/") for n in zf.namelist()
        )
    sys.exit(0 if has else 1)


def cmd_extract_filestore(zip_path, db):
    target = os.path.join(FILESTORE_ROOT, db)
    shutil.rmtree(target, ignore_errors=True)
    os.makedirs(target, exist_ok=True)
    with zipfile.ZipFile(zip_path) as zf:
        for info in zf.infolist():
            name = info.filename
            if not name.startswith("filestore/") or name.endswith("/"):
                continue
            rel = os.path.relpath(name, "filestore")
            if rel.startswith(".."):  # path traversal — ignora
                continue
            dest = os.path.join(target, rel)
            os.makedirs(os.path.dirname(dest), exist_ok=True)
            with zf.open(info) as src, open(dest, "wb") as dst:
                shutil.copyfileobj(src, dst, CHUNK)
    odoo = pwd.getpwnam("odoo")
    for path in (FILESTORE_ROOT, target):
        try:
            os.chown(path, odoo.pw_uid, odoo.pw_gid)
        except OSError:
            pass
    for root, dirs, files in os.walk(target):
        for name in dirs + files:
            os.chown(os.path.join(root, name), odoo.pw_uid, odoo.pw_gid)


COMMANDS = {
    "zip": cmd_zip,
    "cat": cmd_cat,
    "check": cmd_check,
    "has-filestore": cmd_has_filestore,
    "extract-filestore": cmd_extract_filestore,
}


def main():
    cmd = sys.argv[1] if len(sys.argv) > 1 else ""
    if cmd not in COMMANDS:
        print(__doc__, file=sys.stderr)
        sys.exit(2)
    COMMANDS[cmd](*sys.argv[2:])


if __name__ == "__main__":
    main()
