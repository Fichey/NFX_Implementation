#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NFX - Pobieranie kursow walut z NBP Web API
-------------------------------------------
Odpowiednik logiki Script Task (C#) z pakietu SSIS Load_NBP_FX.dtsx,
zaimplementowany w Pythonie aby uruchomic ETL bez srodowiska SSIS.
Patrz tez: 02_etl/NBP_ScriptTask.cs (kod C# do wklejenia w SSIS).

Funkcje:
  * tabele A i B (mid)  + opcjonalnie C (bid/ask)
  * automatyczny podzial zakresu dat na segmenty <= 93 dni (limit NBP)
  * obsluga 404 (dzien wolny -> pomijamy, nie blad)
  * tylko HTTPS (wymog NBP od 2025-08-01)
  * deduplikacja po (effective_date, code, table_type)

Uruchomienie (pelne archiwum / inicjalizacja):
    python nbp_fetch.py --start 2026-01-01 --end 2026-06-13 --tables A B C --outdir .

Uruchomienie (kolejna iteracja / incremental - tylko ostatni dzien):
    python nbp_fetch.py --last-days 5 --tables A B --outdir .

Wyniki:
    stg_fx_rates.csv          - splaszczone kursy (wejscie do staging.stg_fx_rates)
    nbp_currency_codes.json   - mapa {code: tabela}  (uzywane przez profiler i DIM_Currency)
    dim_currency_seed.csv     - slownik walut (code, nazwa_pl, tabela)
    nbp_fetch_log.txt         - log wykonania (dowod do testow)
"""
import argparse, json, os, io, sys, time
from datetime import date, timedelta, datetime
import requests

BASE = "https://api.nbp.pl/api/exchangerates/tables"
MAX_SPAN = 90          # bezpieczny segment < 93 dni
TIMEOUT = 30
HEADERS = {"Accept": "application/json", "User-Agent": "NFX-DW/1.0"}


def daterange_segments(start: date, end: date, span: int = MAX_SPAN):
    cur = start
    while cur <= end:
        seg_end = min(cur + timedelta(days=span - 1), end)
        yield cur, seg_end
        cur = seg_end + timedelta(days=1)


def fetch_table(table: str, start: date, end: date, log):
    """Zwraca liste rekordow JSON dla tabeli w zadanym zakresie (segmentowanym)."""
    out = []
    for seg_start, seg_end in daterange_segments(start, end):
        url = f"{BASE}/{table}/{seg_start.isoformat()}/{seg_end.isoformat()}/?format=json"
        try:
            r = requests.get(url, headers=HEADERS, timeout=TIMEOUT)
        except requests.RequestException as e:
            log(f"  [ERR ] {table} {seg_start}..{seg_end} -> wyjatek: {e}")
            continue
        if r.status_code == 404:
            log(f"  [SKIP] {table} {seg_start}..{seg_end} -> 404 (brak danych w zakresie)")
            continue
        if r.status_code != 200:
            log(f"  [WARN] {table} {seg_start}..{seg_end} -> HTTP {r.status_code}")
            continue
        data = r.json()
        out.extend(data)
        days = (seg_end - seg_start).days + 1
        log(f"  [ OK ] {table} {seg_start}..{seg_end} ({days} dni) -> {len(data)} tabel")
        time.sleep(0.2)  # uprzejmosc wobec API
    return out


def flatten(table_payload, table_type):
    rows = []
    for tbl in table_payload:
        no = tbl.get("no")
        eff = tbl.get("effectiveDate")
        trading = tbl.get("tradingDate")  # tylko tabela C
        for rt in tbl.get("rates", []):
            rows.append({
                "table_type": table_type,
                "table_no": no,
                "effective_date": eff,
                "trading_date": trading,
                "code": rt.get("code"),
                "currency_name_pl": rt.get("currency"),
                "mid": rt.get("mid"),
                "bid": rt.get("bid"),
                "ask": rt.get("ask"),
            })
    return rows


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--start")
    ap.add_argument("--end")
    ap.add_argument("--last-days", type=int, default=None,
                    help="tryb incremental: ostatnie N dni do dzisiaj")
    ap.add_argument("--tables", nargs="+", default=["A", "B"])
    ap.add_argument("--outdir", default=".")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)
    log_lines = []

    def log(msg):
        line = f"{datetime.now().isoformat(timespec='seconds')} {msg}"
        log_lines.append(line)
        print(line, file=sys.stderr)

    if args.last_days is not None:
        end = date.today()
        start = end - timedelta(days=args.last_days)
    else:
        start = datetime.strptime(args.start, "%Y-%m-%d").date()
        end = datetime.strptime(args.end, "%Y-%m-%d").date()

    log(f"=== NBP FETCH start ===  zakres {start}..{end}  tabele={args.tables}")
    log(f"Liczba segmentow (<= {MAX_SPAN} dni): "
        f"{len(list(daterange_segments(start, end)))}")

    all_rows = []
    code_table = {}      # code -> najbardziej "podstawowa" tabela (A>B>C)
    code_name = {}
    rank = {"A": 0, "B": 1, "C": 2}

    for t in args.tables:
        log(f"--- Tabela {t} ---")
        payload = fetch_table(t, start, end, log)
        rows = flatten(payload, t)
        all_rows.extend(rows)
        for rrow in rows:
            c = rrow["code"]
            if c is None:
                continue
            if c not in code_table or rank[t] < rank[code_table[c]]:
                code_table[c] = t
            code_name.setdefault(c, rrow["currency_name_pl"])
        log(f"  Tabela {t}: {len(rows)} wierszy po splaszczeniu")

    # deduplikacja (effective_date, code, table_type)
    seen = set()
    dedup = []
    for r in all_rows:
        k = (r["effective_date"], r["code"], r["table_type"])
        if k in seen:
            continue
        seen.add(k)
        dedup.append(r)
    log(f"Po deduplikacji: {len(dedup)} / {len(all_rows)} wierszy")

    # zapis stg_fx_rates.csv
    import csv
    fx_path = os.path.join(args.outdir, "stg_fx_rates.csv")
    cols = ["table_type", "table_no", "effective_date", "trading_date",
            "code", "currency_name_pl", "mid", "bid", "ask"]
    with io.open(fx_path, "w", encoding="utf-8", newline="") as f:
        w = csv.DictWriter(f, fieldnames=cols)
        w.writeheader()
        for r in sorted(dedup, key=lambda x: (x["effective_date"] or "", x["table_type"], x["code"] or "")):
            w.writerow({k: r.get(k) for k in cols})
    log(f"Zapisano {fx_path}")

    # mapa kodow (dla profilera + DIM_Currency)
    with io.open(os.path.join(args.outdir, "nbp_currency_codes.json"), "w", encoding="utf-8") as f:
        json.dump(code_table, f, ensure_ascii=False, indent=2)
    # rownolegle skopiuj do folderu profilera (uzywany przez profile_nike.py)
    prof_dir = os.path.join(args.outdir, "..", "05_data_profiling")
    if os.path.isdir(prof_dir):
        with io.open(os.path.join(prof_dir, "nbp_currency_codes.json"), "w", encoding="utf-8") as f:
            json.dump(code_table, f, ensure_ascii=False, indent=2)

    # slownik walut (seed do DIM_Currency)
    seed_path = os.path.join(args.outdir, "dim_currency_seed.csv")
    with io.open(seed_path, "w", encoding="utf-8", newline="") as f:
        w = csv.writer(f)
        w.writerow(["currency_code", "currency_name_pl", "nbp_table_type"])
        for c in sorted(code_table):
            w.writerow([c, code_name.get(c, ""), code_table[c]])
    log(f"Zapisano {seed_path}  ({len(code_table)} walut)")

    # statystyki do testu pokrycia
    log(f"Unikalne waluty: {len(code_table)}  "
        f"(A={sum(1 for v in code_table.values() if v=='A')}, "
        f"B={sum(1 for v in code_table.values() if v=='B')}, "
        f"C={sum(1 for v in code_table.values() if v=='C')})")
    eff_dates = sorted({r['effective_date'] for r in dedup if r['effective_date']})
    log(f"Zakres dat notowan: {eff_dates[0] if eff_dates else '-'} .. "
        f"{eff_dates[-1] if eff_dates else '-'}  ({len(eff_dates)} dni roboczych)")
    log("=== NBP FETCH koniec ===")

    with io.open(os.path.join(args.outdir, "nbp_fetch_log.txt"), "w", encoding="utf-8") as f:
        f.write("\n".join(log_lines))


if __name__ == "__main__":
    main()
