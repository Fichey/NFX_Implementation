#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NFX - Zestaw testow funkcjonalnych (uruchamiany na zywej hurtowni NFX_DW)
-------------------------------------------------------------------------
Pokrywa wszystkie warstwy: ETL, hurtownia, BI, raporty + end-to-end,
spojnosc cross-layer oraz scenariusze inicjalizacji / kolejnej iteracji.

Kazdy test ma format wymagany w zaliczeniu:
   (1) Cel  (2) Kroki  (3) Oczekiwany wynik  (4) Potwierdzenie (wartosc rzeczywista)

Wynik: test_results.md (raport) + test_results.json (log maszynowy).
Uruchomienie:  python run_tests.py
"""
import os, sys, json, datetime, io
sys.path.insert(0, os.path.join(os.path.dirname(__file__), "..", "02_etl"))
import pandas as pd
from db_util import connect
import nbp_fetch   # do testu segmentacji 93-dniowej

HERE = os.path.dirname(__file__)
NIKE_CSV = os.path.join(HERE, "..", "05_data_profiling", "nike_product_country.csv")
RESULTS = []


def add(tid, layer, cel, kroki, oczek, passed, actual):
    RESULTS.append(dict(id=tid, layer=layer, cel=cel, kroki=kroki, oczekiwany=oczek,
                        status="PASS" if passed else "FAIL", potwierdzenie=actual))
    print(f"[{'PASS' if passed else 'FAIL'}] {tid} :: {actual}")


def scalar(cur, sql, *p):
    cur.execute(sql, *p)
    row = cur.fetchone()
    return row[0] if row else None


def main():
    conn = connect(); cur = conn.cursor()

    # liczba REKORDOW logicznych w pliku zrodlowym (csv.reader poprawnie obsluguje
    # przelamania linii wewnatrz pol w cudzyslowach – 13 takich rekordow w danych).
    import csv as _csv
    def _csv_count(path):
        if not os.path.exists(path):
            return None
        with open(path, encoding="utf-8", newline="") as _f:
            return sum(1 for _ in _csv.reader(_f)) - 1
    SAMPLE_CSV = os.path.join(HERE, "..", "sample_data", "nike_product_country_sample.csv")
    full_n = _csv_count(NIKE_CSV)
    sample_n = _csv_count(SAMPLE_CSV)

    # ---------------- WARSTWA ETL ----------------
    # Uwaga: staging to tabela tymczasowa - trzyma OSTATNIO zaladowana partie (pelny plik LUB probka).
    # Test sprawdza, ze staging DOKLADNIE odpowiada jednemu ze znanych zrodel (brak gubienia wierszy).
    stg = scalar(cur, "SELECT COUNT(*) FROM staging.stg_nike_prices")
    match_full = (full_n is not None and stg == full_n)
    match_sample = (sample_n is not None and stg == sample_n)
    which = "pelny plik" if match_full else ("probka" if match_sample else "BRAK dopasowania")
    add("T-ETL-01", "ETL / CSV",
        "Kompletnosc ekstrakcji: liczba wierszy w staging = liczba rekordow zaladowanego pliku",
        "COUNT(*) staging vs liczba rekordow CSV (pelny lub probka)",
        "rownosc z jednym ze zrodel",
        match_full or match_sample,
        f"staging={stg:,} -> {which} (pelny={full_n} / probka={sample_n})")

    rej = scalar(cur, "SELECT COUNT(*) FROM staging.error_log")
    valid_stg = scalar(cur, """SELECT COUNT(*) FROM staging.stg_nike_prices
        WHERE style_color IS NOT NULL AND TRY_CONVERT(decimal(12,2), price_local) > 0""")
    matched = scalar(cur, """
        SELECT COUNT(*) FROM staging.stg_nike_prices s
        JOIN dw.DIM_Product   p ON p.style_color = s.style_color AND p.is_current = 1
        JOIN dw.DIM_Geography g ON g.country_code = s.country_code
        JOIN dw.DIM_Date      d ON d.full_date = TRY_CONVERT(date, s.snapshot_date)
        JOIN dw.FACT_Prices   f ON f.product_key = p.product_key AND f.geo_key = g.geo_key AND f.date_key = d.date_key
        WHERE TRY_CONVERT(decimal(12,2), s.price_local) > 0""")
    add("T-ETL-02", "ETL / transformacja",
        "Brak gubienia danych: kazdy poprawny wiersz staging ma odpowiednik w FACT_Prices",
        "valid(staging) = dopasowane do FACT_Prices; niepoprawne -> error_log",
        "kazdy poprawny wiersz obecny w fakcie",
        matched == valid_stg, f"valid_staging={valid_stg:,} dopasowane_w_fakcie={matched:,}; odrzucone={rej:,}")

    bad = scalar(cur, "SELECT COUNT(*) FROM dw.FACT_Prices WHERE local_price<=0")
    rej_reasons = scalar(cur, "SELECT COUNT(*) FROM staging.error_log WHERE reject_reason LIKE 'price%'")
    add("T-ETL-03", "ETL / walidacja",
        "Reguła jakości: ceny <=0 odrzucone do error_log, brak w fakcie",
        "FACT_Prices WHERE local_price<=0  (oczek. 0) oraz error_log z powodem 'price%'",
        "0 zlych cen w fakcie; wszystkie odrzuty opisane",
        bad == 0 and rej_reasons == rej, f"zle_w_fakcie={bad}; odrzuty_price={rej_reasons}/{rej}")

    a_curr = scalar(cur, "SELECT COUNT(DISTINCT currency_key) FROM dw.FACT_ExchangeRates WHERE table_type='A'")
    a_null = scalar(cur, "SELECT COUNT(*) FROM dw.FACT_ExchangeRates WHERE table_type='A' AND mid_rate IS NULL")
    add("T-ETL-04", "ETL / NBP",
        "Pobranie kursow: tabela A pokrywa >=32 walut, brak NULL w mid",
        "DISTINCT currency_key oraz NULL mid w FACT_ExchangeRates (table_type='A')",
        ">=32 walut, 0 NULL mid",
        a_curr >= 32 and a_null == 0, f"walut_A={a_curr}; null_mid_A={a_null}")

    # 93-dniowa segmentacja (test kodu fetchera)
    from datetime import date
    segs = list(nbp_fetch.daterange_segments(date(2026,1,1), date(2026,6,29)))  # 180 dni
    over = [s for s in segs if (s[1]-s[0]).days+1 > 93]
    add("T-ETL-05", "ETL / limit 93 dni",
        "Zapytanie o 180 dni dzielone na segmenty <=93 dni (limit NBP, brak 400)",
        "nbp_fetch.daterange_segments(2026-01-01, 2026-06-29)",
        ">=2 segmenty, kazdy <=93 dni",
        len(segs) >= 2 and not over, f"segmentow={len(segs)}, max_dni={max((s[1]-s[0]).days+1 for s in segs)}")

    # ---------------- WARSTWA HURTOWNI ----------------
    # SCD2 – w transakcji z ROLLBACK (nie zmienia stanu hurtowni)
    # WAZNE: produkt do testu bierzemy z biezacego staging (gwarancja, ze UPDATE go trafi)
    sc = scalar(cur, "SELECT TOP 1 style_color FROM staging.stg_nike_prices WHERE style_color IS NOT NULL ORDER BY style_color")
    before = scalar(cur, "SELECT COUNT(*) FROM dw.DIM_Product WHERE style_color=?", sc)
    cur.execute("BEGIN TRANSACTION")
    cur.execute("UPDATE staging.stg_nike_prices SET color_name='__SCD2_TEST__' WHERE style_color=?", sc)
    cur.execute("EXEC dw.usp_LoadDimProduct_SCD2 @load_date=?", (datetime.date.today()+datetime.timedelta(days=1)).isoformat())
    cnt = scalar(cur, "SELECT COUNT(*) FROM dw.DIM_Product WHERE style_color=?", sc)
    closed = scalar(cur, "SELECT COUNT(*) FROM dw.DIM_Product WHERE style_color=? AND is_current=0 AND valid_to IS NOT NULL", sc)
    newcur = scalar(cur, "SELECT COUNT(*) FROM dw.DIM_Product WHERE style_color=? AND is_current=1 AND color_name='__SCD2_TEST__'", sc)
    cur.execute("ROLLBACK TRANSACTION")
    add("T-DW-01", "Hurtownia / SCD2",
        "DIM_Product SCD Typ 2: zmiana atrybutu zamyka stary rekord i tworzy nowy",
        f"zmien color_name dla '{sc}', wywolaj usp_LoadDimProduct_SCD2 (load_date=jutro)",
        "stary is_current=0+valid_to; nowy is_current=1 z nowa wartoscia; +1 wiersz",
        cnt == before+1 and closed >= 1 and newcur == 1,
        f"przed={before} po={cnt}; zamkniete={closed}; nowy_aktualny={newcur}")

    # przeliczenie price_pln (USD) wzgledem kursu snapshotu
    usd_rate = scalar(cur, """
        SELECT TOP 1 f.mid_rate FROM dw.FACT_ExchangeRates f JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
        WHERE c.currency_code='USD' AND f.table_type='A'
          AND f.effective_date <= (SELECT MAX(full_date) FROM dw.DIM_Date d JOIN dw.FACT_Prices p ON p.date_key=d.date_key)
        ORDER BY f.effective_date DESC""")
    maxdiff = scalar(cur, """
        SELECT MAX(ABS(f.price_pln - f.local_price*?))
        FROM dw.FACT_Prices f JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
        WHERE c.currency_code='USD'""", float(usd_rate))
    add("T-DW-02", "Hurtownia / przeliczenie",
        "Poprawnosc transformacji: price_pln = local_price * kurs_mid (USD)",
        "MAX(ABS(price_pln - local_price*kurs_USD)) dla wszystkich rekordow USD",
        "odchylenie <= 0,001 PLN (zaokraglenie)",
        float(maxdiff) <= 0.001, f"kurs_USD={usd_rate}; max_odchylenie={maxdiff}")

    fx_cnt = scalar(cur, "SELECT COUNT(*) FROM dw.FACT_ExchangeRates")
    fx_dis = scalar(cur, "SELECT COUNT(*) FROM (SELECT DISTINCT effective_date,currency_key,table_type FROM dw.FACT_ExchangeRates) t")
    add("T-DW-03", "Hurtownia / dedup FX",
        "Deduplikacja FX: brak duplikatow (data+waluta+tabela)",
        "COUNT(*) vs COUNT(DISTINCT effective_date,currency_key,table_type)",
        "rownosc",
        fx_cnt == fx_dis, f"count={fx_cnt:,} distinct={fx_dis:,}")

    orphans = scalar(cur, """
        SELECT COUNT(*) FROM dw.FACT_Prices f
        WHERE NOT EXISTS(SELECT 1 FROM dw.DIM_Product p WHERE p.product_key=f.product_key)
           OR NOT EXISTS(SELECT 1 FROM dw.DIM_Geography g WHERE g.geo_key=f.geo_key)
           OR NOT EXISTS(SELECT 1 FROM dw.DIM_Currency c WHERE c.currency_key=f.currency_key)
           OR NOT EXISTS(SELECT 1 FROM dw.DIM_Date d WHERE d.date_key=f.date_key)
           OR NOT EXISTS(SELECT 1 FROM dw.DIM_Category k WHERE k.category_key=f.category_key)""")
    add("T-DW-04", "Hurtownia / integralnosc",
        "Integralnosc referencyjna: brak osieroconych kluczy obcych w FACT_Prices",
        "FACT_Prices bez dopasowania w ktoryms z 5 wymiarow",
        "0 osieroconych wierszy",
        orphans == 0, f"osierocone={orphans}")

    # ---------------- WARSTWA BI ----------------
    # marza BI vs reczne min/max z faktow dla konkretnego produktu
    prod = scalar(cur, "SELECT TOP 1 style_color FROM bi.v_product_arbitrage WHERE n_markets>=8 ORDER BY margin_pct DESC")
    bi_margin = scalar(cur, "SELECT margin_pct FROM bi.v_product_arbitrage WHERE style_color=?", prod)
    man = cur.execute("""
        SELECT MIN(price_pln), MAX(price_pln) FROM dw.FACT_Prices f
        JOIN dw.DIM_Product p ON p.product_key=f.product_key
        WHERE p.style_color=? AND f.price_pln BETWEEN 1 AND 50000""", prod).fetchone()
    man_margin = round(100*(float(man[1])-float(man[0]))/float(man[0]),1)
    add("T-BI-01", "BI / miara marzy",
        "Poprawnosc miary: marza z widoku BI = reczne (max-min)/min z faktow",
        f"porownaj bi.v_product_arbitrage.margin_pct dla '{prod}' z obliczeniem recznym",
        "zgodnosc <= 0,5 p.p.",
        abs(float(bi_margin)-man_margin) <= 0.5, f"BI={bi_margin}% reczne={man_margin}%")

    out = scalar(cur, "SELECT COUNT(*) FROM bi.v_product_arbitrage WHERE max_price_pln>50000")
    add("T-BI-02", "BI / outliery",
        "Reguła outlierow: widok arbitrazu nie zawiera cen-sentineli (>50000 PLN)",
        "bi.v_product_arbitrage WHERE max_price_pln>50000",
        "0 wierszy",
        out == 0, f"outliery_w_widoku={out}")

    # ---------------- SPOJNOSC CROSS-LAYER ----------------
    # wez (produkt, kraj) z biezacego staging, ktory rozwiazuje sie do wymiarow
    row = cur.execute("""SELECT TOP 1 s.style_color, s.country_code
        FROM staging.stg_nike_prices s
        JOIN dw.DIM_Product p ON p.style_color = s.style_color AND p.is_current = 1
        WHERE s.style_color IS NOT NULL AND TRY_CONVERT(decimal(12,2), s.price_local) > 0
        ORDER BY s.style_color, s.country_code""").fetchone()
    sc2, cc2 = (row[0], row[1]) if row else (None, None)
    stg_price  = scalar(cur, "SELECT price_local FROM staging.stg_nike_prices WHERE style_color=? AND country_code=?", sc2, cc2)
    fact_price = scalar(cur, """SELECT f.local_price FROM dw.FACT_Prices f JOIN dw.DIM_Product p ON p.product_key=f.product_key
        JOIN dw.DIM_Geography g ON g.geo_key=f.geo_key WHERE p.style_color=? AND g.country_code=?""", sc2, cc2)
    bi_price   = scalar(cur, "SELECT local_price FROM bi.v_price_enriched WHERE style_color=? AND country_code=?", sc2, cc2)
    # cena ze ZRODLA: szukaj w pelnym pliku, potem w probce (probka jest podzbiorem pelnego)
    src_price = None
    for fpath in (NIKE_CSV, SAMPLE_CSV):
        if fpath and os.path.exists(fpath):
            d = pd.read_csv(fpath, dtype=str)
            m = d[(d.style_color == sc2) & (d.country_code == cc2)]
            if len(m):
                src_price = float(m["price_local"].iloc[0]); break
    vals = [float(v) for v in (src_price, stg_price, fact_price, bi_price) if v is not None]
    consistent = len(vals) >= 3 and (max(vals) - min(vals) < 0.01)
    add("T-XL-01", "Spojnosc (cross-layer)",
        "Ta sama cena na kazdym etapie: plik -> staging -> fakt -> widok BI",
        f"sledz {sc2}/{cc2} przez warstwy",
        "identyczna cena lokalna",
        consistent, f"plik={src_price} staging={stg_price} fakt={fact_price} BI={bi_price}")

    # ---------------- SCENARIUSZ: KOLEJNA ITERACJA (incremental dedup) ----------------
    before_fx = scalar(cur, "SELECT COUNT(*) FROM dw.FACT_ExchangeRates")
    cur.execute("BEGIN TRANSACTION")
    cur.execute("EXEC dw.usp_LoadFactExchangeRates")     # ponowne ladowanie z tego samego staging
    after_fx = scalar(cur, "SELECT COUNT(*) FROM dw.FACT_ExchangeRates")
    cur.execute("ROLLBACK TRANSACTION")
    add("T-INC-01", "Scenariusz / incremental",
        "Kolejna iteracja: ponowne ladowanie FX nie tworzy duplikatow (idempotencja)",
        "ponowne EXEC usp_LoadFactExchangeRates na tym samym staging (w transakcji)",
        "przyrost = 0 wierszy",
        before_fx == after_fx, f"przed={before_fx:,} po={after_fx:,} przyrost={after_fx-before_fx}")

    # ---------------- END-TO-END ----------------
    run = cur.execute("""SELECT TOP 1 status, rows_in, rows_out, rows_rejected, load_type
                         FROM staging.etl_run_log ORDER BY run_id DESC""").fetchone()
    kpi = cur.execute("SELECT products, markets, arbitrage_products, opportunities_gt20 FROM bi.v_kpi_summary").fetchone()
    e2e_ok = run[0]=="SUCCESS" and kpi[0]>0 and kpi[2]>0
    add("T-E2E-01", "End-to-end",
        "Calosciowe dzialanie: ETL SUCCESS i warstwa BI zwraca sensowne KPI",
        "etl_run_log (ostatni przebieg) + bi.v_kpi_summary",
        "status SUCCESS, produkty>0, okazje>0",
        e2e_ok, f"status={run[0]}; produkty={kpi[0]:,}; rynki={kpi[1]}; okazje>20%={kpi[3]:,}")

    conn.close()
    write_md()
    npass = sum(1 for r in RESULTS if r["status"]=="PASS")
    print(f"\n=== WYNIK: {npass}/{len(RESULTS)} testow PASS ===")
    with io.open(os.path.join(HERE,"test_results.json"),"w",encoding="utf-8") as f:
        json.dump({"generated": datetime.datetime.now().isoformat(),
                   "passed": npass, "total": len(RESULTS), "tests": RESULTS}, f,
                  ensure_ascii=False, indent=2)


def write_md():
    npass = sum(1 for r in RESULTS if r["status"]=="PASS")
    L=[]; a=L.append
    a("# NFX — Wyniki testów funkcjonalnych\n")
    a(f"_Wygenerowano:_ {datetime.datetime.now():%Y-%m-%d %H:%M}  ·  "
      f"_Środowisko:_ SQL Server 2019 Developer, baza `NFX_DW`  ·  "
      f"_Uruchomienie:_ `python 06_tests/run_tests.py`\n")
    a(f"## Podsumowanie: **{npass}/{len(RESULTS)} PASS**\n")
    a("| # | Warstwa | Cel | Status | Potwierdzenie (wartość rzeczywista) |")
    a("|---|---|---|---|---|")
    for r in RESULTS:
        a(f"| {r['id']} | {r['layer']} | {r['cel']} | {'✅ '+r['status'] if r['status']=='PASS' else '❌ '+r['status']} | `{r['potwierdzenie']}` |")
    a("\n---\n## Szczegóły testów\n")
    for r in RESULTS:
        a(f"### {r['id']} — {r['layer']}")
        a(f"- **(1) Cel:** {r['cel']}")
        a(f"- **(2) Kroki:** {r['kroki']}")
        a(f"- **(3) Oczekiwany wynik:** {r['oczekiwany']}")
        a(f"- **(4) Potwierdzenie:** `{r['potwierdzenie']}` → **{r['status']}**\n")
    a("\n## Scenariusze ładowania")
    a("- **Inicjalizacja (INITIAL):** `python 02_etl/run_etl.py --mode initial` — puste tabele → pełne załadowanie (log: `staging.etl_run_log`).")
    a("- **Kolejna iteracja (INCREMENTAL):** `python 02_etl/run_etl.py --mode incremental` — deduplikacja FX (T-INC-01) chroni przed duplikatami; katalog ładowany ze SCD2 (T-DW-01).")
    a("\n## Dowody dodatkowe")
    a("- Log ETL: `_evidence/etl_run_*.txt` oraz tabela `staging.etl_run_log`.")
    a("- Log pobierania NBP (segmentacja 93 dni): `02_etl/nbp_fetch_log.txt`.")
    a("- Podglądy raportów: `07_reports/report_*.png`.")
    with io.open(os.path.join(HERE,"test_results.md"),"w",encoding="utf-8") as f:
        f.write("\n".join(L))


if __name__=="__main__":
    main()
