#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NFX - Orkiestrator ETL (odpowiednik Control Flow obu pakietow SSIS)
-------------------------------------------------------------------
Implementuje w Pythonie te sama logike, co pakiety SSIS, aby uruchomic
pelny przeplyw bez srodowiska SSIS. Kroki:

  1. Otworz wpis audytu (staging.etl_run_log, status RUNNING)
  2. [Pakiet #2 - FX]  TRUNCATE staging.stg_fx_rates  -> BULK load stg_fx_rates.csv
  3. [Pakiet #1 - CSV] TRUNCATE staging.stg_nike_prices -> BULK load nike_product_country.csv
  4. EXEC dw.usp_LoadWarehouse  (wymiary + fakty + przeliczenia + SCD)
  5. Zamknij wpis audytu (SUCCESS / FAILED) z licznikami

Scenariusze:
  --mode initial      pelne ladowanie (inicjalizacja pustej hurtowni)
  --mode incremental  kolejna iteracja (deduplikacja na poziomie faktow chroni przed dublami)

Uruchomienie:
  python run_etl.py --mode initial
  python run_etl.py --mode incremental --fx-csv stg_fx_rates_new.csv
"""
import argparse, os, sys, datetime
import pandas as pd
import pyodbc
from db_util import connect, load_config

NIKE_COLS = ["style_color","country_code","snapshot_date","model_number","product_name",
             "color_name","gender_segment","category","subcategory","currency",
             "price_local","sale_price_local","discount_pct","in_stock","availability_level"]

FX_COLS = ["table_type","table_no","effective_date","trading_date","code",
           "currency_name_pl","mid","bid","ask"]


def log(msg):
    print(f"{datetime.datetime.now():%Y-%m-%d %H:%M:%S} {msg}", flush=True)


def _clean(v):
    """Wymus natywny python str albo None (pandas 3.0 zwraca pd.NA / typy numpy)."""
    if v is None:
        return None
    try:
        if pd.isna(v):
            return None
    except (TypeError, ValueError):
        pass
    s = str(v)
    return None if s == "" else s


def df_to_rows(df, cols):
    out = []
    for r in df[cols].itertuples(index=False, name=None):
        out.append(tuple(_clean(v) for v in r))
    return out


def bulk_load(cur, table, cols, rows, batch_id):
    placeholders = ",".join("?" * (len(cols) + 1))   # +1 = load_batch_id
    sql = f"INSERT INTO {table} ({','.join(cols)}, load_batch_id) VALUES ({placeholders})"
    cur.fast_executemany = True
    # Jawne typy parametrow: wszystkie kolumny tekstowe -> NVARCHAR(4000), batch_id -> INT.
    # Bez tego fast_executemany wnioskuje typ z 1. wiersza (NULL-e psuja wnioskowanie).
    cur.setinputsizes([(pyodbc.SQL_WVARCHAR, 4000, 0)] * len(cols) + [(pyodbc.SQL_INTEGER, 0, 0)])
    data = [r + (batch_id,) for r in rows]
    CH = 20000
    for i in range(0, len(data), CH):
        cur.executemany(sql, data[i:i+CH])
    cur.setinputsizes(None)   # wyczysc, by nie wplywac na kolejne zapytania (audyt)
    return len(data)


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--mode", choices=["initial", "incremental"], default="initial")
    ap.add_argument("--nike-csv", default=None)
    ap.add_argument("--fx-csv", default=None)
    ap.add_argument("--skip-nike", action="store_true", help="laduj tylko FX")
    ap.add_argument("--load-date", default=None, help="data ladowania (SCD2), domyslnie dzis")
    args = ap.parse_args()

    cfg = load_config()
    here = os.path.dirname(__file__)
    nike_csv = args.nike_csv or os.path.join(here, cfg["nike_csv"])
    fx_csv   = args.fx_csv   or os.path.join(here, cfg["fx_csv"])
    load_date = args.load_date or datetime.date.today().isoformat()

    conn = connect(cfg)
    cur = conn.cursor()

    # 1. audyt - start
    cur.execute("""INSERT INTO staging.etl_run_log (package_name, load_type, start_time, status)
                   OUTPUT INSERTED.run_id VALUES (?,?,?,?)""",
                "run_etl.py", args.mode.upper(), datetime.datetime.now(), "RUNNING")
    run_id = cur.fetchone()[0]
    conn.commit()
    log(f"=== ETL start (run_id={run_id}, mode={args.mode}) ===")

    rows_in = rows_out = rows_rej = 0
    try:
        # 2. FX staging
        log(f"FX: TRUNCATE staging.stg_fx_rates + load {os.path.basename(fx_csv)}")
        cur.execute("TRUNCATE TABLE staging.stg_fx_rates")
        fx = pd.read_csv(fx_csv, dtype=str, keep_default_na=False, na_values=[""])
        fx_rows = df_to_rows(fx, FX_COLS)
        n_fx = bulk_load(cur, "staging.stg_fx_rates", FX_COLS, fx_rows, run_id)
        conn.commit()
        log(f"FX: zaladowano {n_fx:,} wierszy do staging")
        rows_in += n_fx

        # 3. Nike catalogue staging
        if not args.skip_nike:
            log(f"CATALOGUE: TRUNCATE staging.stg_nike_prices + load {os.path.basename(nike_csv)}")
            cur.execute("TRUNCATE TABLE staging.stg_nike_prices")
            nk = pd.read_csv(nike_csv, dtype=str, keep_default_na=False, na_values=[""])
            # higiena: pusta podkategoria -> '(Unspecified)' (gwarancja zlaczenia z DIM_Category)
            if "subcategory" in nk.columns:
                nk["subcategory"] = nk["subcategory"].fillna("(Unspecified)").replace("", "(Unspecified)")
            nk_rows = df_to_rows(nk, NIKE_COLS)
            n_nk = bulk_load(cur, "staging.stg_nike_prices", NIKE_COLS, nk_rows, run_id)
            conn.commit()
            log(f"CATALOGUE: zaladowano {n_nk:,} wierszy do staging")
            rows_in += n_nk

        # 4. ladowanie wymiarow + faktow
        log("DW: EXEC dw.usp_LoadWarehouse ...")
        cur.execute("EXEC dw.usp_LoadWarehouse @load_batch_id=?, @load_date=?", run_id, load_date)
        conn.commit()

        # liczniki wynikowe
        rows_out = cur.execute("SELECT COUNT(*) FROM dw.FACT_Prices").fetchval() + \
                   cur.execute("SELECT COUNT(*) FROM dw.FACT_ExchangeRates").fetchval()
        rows_rej = cur.execute("SELECT COUNT(*) FROM staging.error_log WHERE load_batch_id=?", run_id).fetchval()

        cur.execute("""UPDATE staging.etl_run_log
                       SET end_time=?, rows_in=?, rows_out=?, rows_rejected=?, status='SUCCESS',
                           message='OK'
                       WHERE run_id=?""",
                    datetime.datetime.now(), rows_in, rows_out, rows_rej, run_id)
        conn.commit()
        log(f"=== ETL SUCCESS (run_id={run_id}) rows_in={rows_in:,} fact_rows={rows_out:,} rejected={rows_rej:,} ===")

    except Exception as e:
        conn.rollback()
        cur.execute("""UPDATE staging.etl_run_log SET end_time=?, status='FAILED', message=?
                       WHERE run_id=?""", datetime.datetime.now(), str(e)[:480], run_id)
        conn.commit()
        log(f"!!! ETL FAILED: {e}")
        raise
    finally:
        conn.close()


if __name__ == "__main__":
    main()
