#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
export_firebird.py
===================

Скрипт выгружает из базы данных Firebird:
  1) метаданные — таблицы, колонки, типы, первичные/внешние ключи, индексы,
     представления (views), исходники хранимых процедур и триггеров;
  2) выборку данных — не более N строк на таблицу (по умолчанию 1000).

Результат складывается в папку, а затем упаковывается в один .zip —
его удобно передать для анализа структуры базы.

Требуется пакет firebird-driver:
    pip install -r requirements.txt

ПРИМЕР ЗАПУСКА
--------------
    python export_firebird.py \
        --database /path/to/database.fdb \
        --host 127.0.0.1 \
        --user SYSDBA \
        --password masterkey \
        --output export_result \
        --mask

Пароль лучше не передавать в командной строке (он попадёт в историю shell),
а задать через переменную окружения:
    export FB_PASSWORD=masterkey
    python export_firebird.py --database /path/to/db.fdb --user SYSDBA

ВАЖНО (данные кредитной организации)
-------------------------------------
Выгружаемые данные могут содержать персональные и финансовые сведения
(ФИО, паспортные данные, номера счетов/карт, суммы и т.п.).
По умолчанию рекомендуется использовать флаг --mask, который заменяет
значения в колонках с "подозрительными" именами (паспорт, снилс, инн,
карта, телефон, email, адрес, счет и т.д.) на маскированные плейсхолдеры,
сохраняя при этом длину/тип данных, где это возможно, для анализа структуры.
Флаг --mask не гарантирует полной анонимизации — перед передачей выгрузки
за пределы организации файл стоит просмотреть самостоятельно.
"""

import argparse
import csv
import datetime
import decimal
import getpass
import os
import re
import shutil
import sys
import zipfile
from dataclasses import dataclass, field

try:
    import firebird.driver as fbd
except ImportError:
    print(
        "Не найден пакет firebird-driver.\n"
        "Установите зависимости:  pip install -r requirements.txt",
        file=sys.stderr,
    )
    sys.exit(1)


# ---------------------------------------------------------------------------
# Настройки маскировки
# ---------------------------------------------------------------------------

# Подстроки в именах колонок (в нижнем регистре), которые считаем
# потенциально чувствительными персональными/финансовыми данными.
SENSITIVE_NAME_PATTERNS = [
    "passport", "pasport", "паспорт",
    "snils", "снилс",
    "inn", "инн",
    "card", "карт",  # номер карты
    "phone", "телефон", "tel",
    "email", "e_mail", "почта",
    "address", "адрес",
    "account", "счет", "счёт", "iban", "rs", "ks",
    "fio", "фио", "surname", "фамил", "фамилия",
    "name", "имя", "отчество", "patronymic",
    "birth", "рожден", "dob",
    "salary", "зарплат", "доход", "income",
    "balance", "баланс",
    "sum", "сумма", "amount",
]


def is_sensitive_column(column_name: str) -> bool:
    name = column_name.lower()
    return any(pat in name for pat in SENSITIVE_NAME_PATTERNS)


def mask_value(value):
    """Маскирует значение, стараясь сохранить тип/длину для анализа структуры."""
    if value is None:
        return None
    if isinstance(value, str):
        if len(value) == 0:
            return value
        return "*" * min(len(value), 8)
    if isinstance(value, (int,)):
        return 0
    if isinstance(value, decimal.Decimal):
        return decimal.Decimal("0")
    if isinstance(value, float):
        return 0.0
    if isinstance(value, (datetime.date, datetime.datetime, datetime.time)):
        return value  # даты обычно не столь критичны для структуры/сроков
    return "***"


# ---------------------------------------------------------------------------
# Работа с системными таблицами Firebird (метаданные)
# ---------------------------------------------------------------------------

FIELD_TYPE_NAMES = {
    7: "SMALLINT",
    8: "INTEGER",
    9: "QUAD",
    10: "FLOAT",
    11: "D_FLOAT",
    12: "DATE",
    13: "TIME",
    14: "CHAR",
    16: "BIGINT",       # либо NUMERIC/DECIMAL при заданном precision/sub_type
    23: "BOOLEAN",
    27: "DOUBLE PRECISION",
    35: "TIMESTAMP",
    37: "VARCHAR",
    261: "BLOB",
}

BLOB_SUBTYPE_NAMES = {
    0: "BINARY",
    1: "TEXT",
}


def sql_type_name(field_type, sub_type, precision, scale, length, char_length):
    base = FIELD_TYPE_NAMES.get(field_type, f"UNKNOWN({field_type})")
    if field_type == 16 and sub_type in (1, 2):
        # NUMERIC/DECIMAL хранятся как BIGINT с sub_type и scale
        kind = "NUMERIC" if sub_type == 1 else "DECIMAL"
        prec = precision if precision else 18
        sc = -scale if scale else 0
        return f"{kind}({prec},{sc})"
    if field_type in (7, 8) and sub_type in (1, 2):
        kind = "NUMERIC" if sub_type == 1 else "DECIMAL"
        prec = precision if precision else (4 if field_type == 7 else 9)
        sc = -scale if scale else 0
        return f"{kind}({prec},{sc})"
    if field_type in (14, 37):
        ln = char_length if char_length else length
        return f"{base}({ln})"
    if field_type == 261:
        sub_name = BLOB_SUBTYPE_NAMES.get(sub_type, str(sub_type))
        return f"BLOB SUB_TYPE {sub_type} ({sub_name})"
    return base


@dataclass
class ColumnInfo:
    name: str
    position: int
    not_null: bool
    default_source: str
    type_str: str
    field_type: int
    sub_type: int
    is_pk: bool = False


@dataclass
class TableInfo:
    name: str
    kind: str  # "TABLE" or "VIEW"
    columns: list = field(default_factory=list)
    pk_fields: list = field(default_factory=list)
    fks: list = field(default_factory=list)  # list of dict
    indexes: list = field(default_factory=list)  # list of dict


def fetch_all_dicts(cur):
    cols = [d[0] for d in cur.description]
    return [dict(zip(cols, row)) for row in cur.fetchall()]


def get_tables_and_views(con):
    cur = con.cursor()
    cur.execute(
        """
        SELECT TRIM(r.RDB$RELATION_NAME) AS NAME,
               CASE WHEN r.RDB$VIEW_BLR IS NULL THEN 'TABLE' ELSE 'VIEW' END AS KIND
        FROM RDB$RELATIONS r
        WHERE (r.RDB$SYSTEM_FLAG IS NULL OR r.RDB$SYSTEM_FLAG = 0)
        ORDER BY 2, 1
        """
    )
    return fetch_all_dicts(cur)


def get_columns(con, relation_name):
    cur = con.cursor()
    cur.execute(
        """
        SELECT
            TRIM(rf.RDB$FIELD_NAME)      AS FIELD_NAME,
            rf.RDB$FIELD_POSITION        AS POS,
            rf.RDB$NULL_FLAG             AS NOT_NULL_FLAG,
            rf.RDB$DEFAULT_SOURCE        AS DEFAULT_SRC,
            f.RDB$FIELD_TYPE             AS FIELD_TYPE,
            f.RDB$FIELD_SUB_TYPE         AS SUB_TYPE,
            f.RDB$FIELD_LENGTH           AS FLEN,
            f.RDB$FIELD_PRECISION        AS FPREC,
            f.RDB$FIELD_SCALE            AS FSCALE,
            f.RDB$CHARACTER_LENGTH       AS CHAR_LEN
        FROM RDB$RELATION_FIELDS rf
        JOIN RDB$FIELDS f ON f.RDB$FIELD_NAME = rf.RDB$FIELD_SOURCE
        WHERE rf.RDB$RELATION_NAME = ?
        ORDER BY rf.RDB$FIELD_POSITION
        """,
        (relation_name,),
    )
    rows = fetch_all_dicts(cur)
    columns = []
    for r in rows:
        type_str = sql_type_name(
            r["FIELD_TYPE"], r["SUB_TYPE"], r["FPREC"], r["FSCALE"], r["FLEN"], r["CHAR_LEN"]
        )
        default_src = r["DEFAULT_SRC"]
        if default_src is not None and not isinstance(default_src, str):
            # может прийти как BLOB-объект для длинных выражений
            try:
                default_src = default_src.read().decode("utf-8", errors="replace")
            except Exception:
                default_src = str(default_src)
        columns.append(
            ColumnInfo(
                name=r["FIELD_NAME"],
                position=r["POS"],
                not_null=bool(r["NOT_NULL_FLAG"]),
                default_source=(default_src or "").strip(),
                type_str=type_str,
                field_type=r["FIELD_TYPE"],
                sub_type=r["SUB_TYPE"] or 0,
            )
        )
    return columns


def get_primary_key(con, relation_name):
    cur = con.cursor()
    cur.execute(
        """
        SELECT TRIM(s.RDB$FIELD_NAME) AS FIELD_NAME
        FROM RDB$RELATION_CONSTRAINTS rc
        JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME
        WHERE rc.RDB$RELATION_NAME = ? AND rc.RDB$CONSTRAINT_TYPE = 'PRIMARY KEY'
        ORDER BY s.RDB$FIELD_POSITION
        """,
        (relation_name,),
    )
    return [r["FIELD_NAME"] for r in fetch_all_dicts(cur)]


def get_foreign_keys(con, relation_name):
    cur = con.cursor()
    cur.execute(
        """
        SELECT
            TRIM(rc.RDB$CONSTRAINT_NAME)  AS FK_NAME,
            TRIM(s.RDB$FIELD_NAME)        AS FIELD_NAME,
            TRIM(rc2.RDB$RELATION_NAME)   AS REF_TABLE,
            TRIM(s2.RDB$FIELD_NAME)       AS REF_FIELD
        FROM RDB$RELATION_CONSTRAINTS rc
        JOIN RDB$REF_CONSTRAINTS refc
             ON refc.RDB$CONSTRAINT_NAME = rc.RDB$CONSTRAINT_NAME
        JOIN RDB$RELATION_CONSTRAINTS rc2
             ON rc2.RDB$CONSTRAINT_NAME = refc.RDB$CONST_NAME_UQ
        JOIN RDB$INDEX_SEGMENTS s
             ON s.RDB$INDEX_NAME = rc.RDB$INDEX_NAME
        JOIN RDB$INDEX_SEGMENTS s2
             ON s2.RDB$INDEX_NAME = rc2.RDB$INDEX_NAME
            AND s2.RDB$FIELD_POSITION = s.RDB$FIELD_POSITION
        WHERE rc.RDB$RELATION_NAME = ? AND rc.RDB$CONSTRAINT_TYPE = 'FOREIGN KEY'
        ORDER BY rc.RDB$CONSTRAINT_NAME, s.RDB$FIELD_POSITION
        """,
        (relation_name,),
    )
    return fetch_all_dicts(cur)


def get_indexes(con, relation_name):
    cur = con.cursor()
    cur.execute(
        """
        SELECT
            TRIM(i.RDB$INDEX_NAME) AS INDEX_NAME,
            i.RDB$UNIQUE_FLAG      AS UNIQUE_FLAG,
            TRIM(s.RDB$FIELD_NAME) AS FIELD_NAME,
            s.RDB$FIELD_POSITION   AS POS
        FROM RDB$INDICES i
        JOIN RDB$INDEX_SEGMENTS s ON s.RDB$INDEX_NAME = i.RDB$INDEX_NAME
        WHERE i.RDB$RELATION_NAME = ?
          AND i.RDB$FOREIGN_KEY IS NULL
        ORDER BY i.RDB$INDEX_NAME, s.RDB$FIELD_POSITION
        """,
        (relation_name,),
    )
    rows = fetch_all_dicts(cur)
    idx_map = {}
    for r in rows:
        idx = idx_map.setdefault(
            r["INDEX_NAME"], {"unique": bool(r["UNIQUE_FLAG"]), "fields": []}
        )
        idx["fields"].append(r["FIELD_NAME"])
    return [{"name": k, **v} for k, v in idx_map.items()]


def get_view_source(con, relation_name):
    cur = con.cursor()
    cur.execute(
        "SELECT RDB$VIEW_SOURCE FROM RDB$RELATIONS WHERE RDB$RELATION_NAME = ?",
        (relation_name,),
    )
    row = cur.fetchone()
    if not row or row[0] is None:
        return ""
    src = row[0]
    if not isinstance(src, str):
        try:
            src = src.read().decode("utf-8", errors="replace")
        except Exception:
            src = str(src)
    return src


def get_procedures(con):
    cur = con.cursor()
    cur.execute(
        """
        SELECT TRIM(RDB$PROCEDURE_NAME) AS NAME, RDB$PROCEDURE_SOURCE AS SRC
        FROM RDB$PROCEDURES
        ORDER BY 1
        """
    )
    result = []
    for row in cur.fetchall():
        name, src = row
        if src is not None and not isinstance(src, str):
            try:
                src = src.read().decode("utf-8", errors="replace")
            except Exception:
                src = str(src)
        result.append((name.strip(), src or ""))
    return result


def get_triggers(con):
    cur = con.cursor()
    cur.execute(
        """
        SELECT TRIM(RDB$TRIGGER_NAME) AS NAME,
               TRIM(RDB$RELATION_NAME) AS REL_NAME,
               RDB$TRIGGER_SOURCE AS SRC
        FROM RDB$TRIGGERS
        WHERE (RDB$SYSTEM_FLAG IS NULL OR RDB$SYSTEM_FLAG = 0)
        ORDER BY 1
        """
    )
    result = []
    for row in cur.fetchall():
        name, rel_name, src = row
        if src is not None and not isinstance(src, str):
            try:
                src = src.read().decode("utf-8", errors="replace")
            except Exception:
                src = str(src)
        result.append((name.strip(), (rel_name or "").strip(), src or ""))
    return result


def build_table_info(con, name, kind):
    info = TableInfo(name=name, kind=kind)
    info.columns = get_columns(con, name)
    if kind == "TABLE":
        info.pk_fields = get_primary_key(con, name)
        info.fks = get_foreign_keys(con, name)
        info.indexes = get_indexes(con, name)
        pk_set = set(info.pk_fields)
        for c in info.columns:
            c.is_pk = c.name in pk_set
    return info


# ---------------------------------------------------------------------------
# Выгрузка данных
# ---------------------------------------------------------------------------

def safe_row_count(con, table_name):
    try:
        cur = con.cursor()
        cur.execute(f'SELECT COUNT(*) FROM "{table_name}"')
        return cur.fetchone()[0]
    except Exception:
        return None


def format_cell(value, blob_sub_type=None):
    if value is None:
        return ""
    if isinstance(value, bytes):
        if blob_sub_type == 1:
            try:
                return value.decode("utf-8", errors="replace")
            except Exception:
                return f"<BLOB BINARY, {len(value)} bytes>"
        return f"<BLOB BINARY, {len(value)} bytes>"
    if hasattr(value, "read"):  # BlobReader (не материализованный BLOB)
        try:
            data = value.read()
            if blob_sub_type == 1:
                return data.decode("utf-8", errors="replace")
            return f"<BLOB BINARY, {len(data)} bytes>"
        except Exception:
            return "<BLOB>"
    return value


def export_table_data(con, table_info: TableInfo, out_path, max_rows, do_mask):
    cur = con.cursor()
    try:
        cur.execute(f'SELECT FIRST {max_rows} * FROM "{table_info.name}"')
    except Exception as e:
        with open(out_path, "w", encoding="utf-8") as f:
            f.write(f"# Ошибка выборки данных из {table_info.name}: {e}\n")
        return 0

    col_names = [d[0] for d in cur.description]
    sub_types = {c.name: c.sub_type for c in table_info.columns if c.field_type == 261}

    n = 0
    with open(out_path, "w", encoding="utf-8", newline="") as f:
        writer = csv.writer(f, delimiter=";")
        writer.writerow(col_names)
        for row in cur.fetchall():
            out_row = []
            for col_name, value in zip(col_names, row):
                cell = format_cell(value, sub_types.get(col_name))
                if do_mask and is_sensitive_column(col_name) and value is not None:
                    cell = mask_value(cell if not isinstance(cell, str) else value)
                out_row.append(cell)
            writer.writerow(out_row)
            n += 1
    return n


# ---------------------------------------------------------------------------
# Формирование метаданных в текстовом виде
# ---------------------------------------------------------------------------

def write_metadata_md(tables, path):
    with open(path, "w", encoding="utf-8") as f:
        f.write("# Метаданные базы данных Firebird\n\n")
        for t in tables:
            f.write(f"## {t.kind}: {t.name}\n\n")
            f.write("| Колонка | Тип | NOT NULL | PK | По умолчанию |\n")
            f.write("|---|---|---|---|---|\n")
            for c in t.columns:
                f.write(
                    f"| {c.name} | {c.type_str} | "
                    f"{'да' if c.not_null else ''} | "
                    f"{'PK' if c.is_pk else ''} | "
                    f"{c.default_source.replace(chr(10), ' ') if c.default_source else ''} |\n"
                )
            f.write("\n")
            if t.fks:
                f.write("Внешние ключи:\n\n")
                for fk in t.fks:
                    f.write(
                        f"- {fk['FK_NAME']}: {fk['FIELD_NAME']} -> "
                        f"{fk['REF_TABLE']}.{fk['REF_FIELD']}\n"
                    )
                f.write("\n")
            if t.indexes:
                f.write("Индексы:\n\n")
                for idx in t.indexes:
                    uniq = "UNIQUE " if idx["unique"] else ""
                    f.write(f"- {uniq}{idx['name']}: ({', '.join(idx['fields'])})\n")
                f.write("\n")
            f.write("---\n\n")


# ---------------------------------------------------------------------------
# main
# ---------------------------------------------------------------------------

def parse_args():
    p = argparse.ArgumentParser(
        description="Выгрузка структуры и образца данных базы Firebird."
    )
    p.add_argument("--database", "-d", required=True, help="Путь к файлу .fdb/.gdb "
                    "или алиас/строка вида host/port:path")
    p.add_argument("--host", default=None, help="Хост сервера Firebird "
                    "(не указывайте для embedded/локального файла)")
    p.add_argument("--port", default=None, type=int, help="Порт сервера (обычно 3050)")
    p.add_argument("--user", "-u", default=os.environ.get("FB_USER", "SYSDBA"))
    p.add_argument("--password", "-p", default=os.environ.get("FB_PASSWORD"))
    p.add_argument("--charset", default="UTF8",
                    help="Кодировка соединения (UTF8, WIN1251, и т.д.)")
    p.add_argument("--output", "-o", default="firebird_export",
                    help="Папка для результата (будет создана)")
    p.add_argument("--max-rows", type=int, default=1000,
                    help="Максимум строк на таблицу (по умолчанию 1000)")
    p.add_argument("--tables", nargs="*", default=None,
                    help="Ограничить выгрузку данных этим списком таблиц "
                         "(метаданные выгружаются по всем)")
    p.add_argument("--no-data", action="store_true",
                    help="Выгрузить только метаданные, без данных таблиц")
    p.add_argument("--count-rows", action="store_true",
                    help="Дополнительно посчитать точное число строк в каждой "
                         "таблице (может быть медленно на больших таблицах)")
    p.add_argument("--mask", action="store_true",
                    help="Маскировать значения в колонках с чувствительными "
                         "именами (паспорт, карта, ИНН, телефон и т.п.)")
    p.add_argument("--zip", dest="make_zip", action="store_true", default=True,
                    help="Упаковать результат в .zip (включено по умолчанию)")
    p.add_argument("--no-zip", dest="make_zip", action="store_false")
    return p.parse_args()


def build_dsn(args):
    if args.host:
        port_part = f"/{args.port}" if args.port else ""
        return f"{args.host}{port_part}:{args.database}"
    return args.database


def main():
    args = parse_args()

    password = args.password
    if not password:
        password = getpass.getpass(f"Пароль для пользователя {args.user}: ")

    dsn = build_dsn(args)
    print(f"Подключение к {dsn} ...")
    try:
        con = fbd.connect(
            database=dsn,
            user=args.user,
            password=password,
            charset=args.charset,
        )
    except Exception as e:
        print(f"Не удалось подключиться к базе: {e}", file=sys.stderr)
        sys.exit(1)

    out_dir = args.output
    data_dir = os.path.join(out_dir, "data")
    if os.path.exists(out_dir):
        shutil.rmtree(out_dir)
    os.makedirs(data_dir, exist_ok=True)

    print("Читаю список таблиц и представлений ...")
    relations = get_tables_and_views(con)
    print(f"Найдено объектов: {len(relations)}")

    tables_info = []
    for rel in relations:
        name, kind = rel["NAME"], rel["KIND"]
        info = build_table_info(con, name, kind)
        tables_info.append(info)
        if kind == "VIEW":
            src = get_view_source(con, name)
            if src:
                with open(os.path.join(out_dir, "views.sql"), "a", encoding="utf-8") as f:
                    f.write(f"-- VIEW {name}\n{src}\n\n")

    print("Пишу файл метаданных (metadata.md) ...")
    write_metadata_md(tables_info, os.path.join(out_dir, "metadata.md"))

    print("Выгружаю исходники хранимых процедур и триггеров ...")
    procs = get_procedures(con)
    if procs:
        with open(os.path.join(out_dir, "procedures.sql"), "w", encoding="utf-8") as f:
            for name, src in procs:
                f.write(f"-- PROCEDURE {name}\n")
                f.write(src if src else "-- (источник недоступен)\n")
                f.write("\n\n")

    triggers = get_triggers(con)
    if triggers:
        with open(os.path.join(out_dir, "triggers.sql"), "w", encoding="utf-8") as f:
            for name, rel_name, src in triggers:
                f.write(f"-- TRIGGER {name} ON {rel_name}\n")
                f.write(src if src else "-- (источник недоступен)\n")
                f.write("\n\n")

    row_counts = {}
    if not args.no_data:
        wanted = set(t.upper() for t in args.tables) if args.tables else None
        only_tables = [t for t in tables_info if t.kind == "TABLE"]
        print(f"Выгружаю данные (до {args.max_rows} строк на таблицу) ...")
        for i, t in enumerate(only_tables, 1):
            if wanted and t.name.upper() not in wanted:
                continue
            out_path = os.path.join(data_dir, f"{t.name}.csv")
            n = export_table_data(con, t, out_path, args.max_rows, args.mask)
            total = None
            if args.count_rows:
                total = safe_row_count(con, t.name)
                row_counts[t.name] = total
            note = f"{n} строк" + (f" из {total}" if total is not None else "")
            print(f"  [{i}/{len(only_tables)}] {t.name}: {note}")

    if args.count_rows and row_counts:
        with open(os.path.join(out_dir, "row_counts.txt"), "w", encoding="utf-8") as f:
            for name, cnt in sorted(row_counts.items()):
                f.write(f"{name}\t{cnt}\n")

    con.close()

    if args.make_zip:
        zip_path = out_dir.rstrip("/\\") + ".zip"
        if os.path.exists(zip_path):
            os.remove(zip_path)
        print(f"Упаковываю результат в {zip_path} ...")
        with zipfile.ZipFile(zip_path, "w", zipfile.ZIP_DEFLATED) as zf:
            for root, _, files in os.walk(out_dir):
                for fn in files:
                    full = os.path.join(root, fn)
                    rel = os.path.relpath(full, out_dir)
                    zf.write(full, rel)
        print(f"Готово: {zip_path}")
    else:
        print(f"Готово: {out_dir}")


if __name__ == "__main__":
    main()
