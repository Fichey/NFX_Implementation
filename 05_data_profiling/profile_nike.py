#!/usr/bin/env python3
# -*- coding: utf-8 -*-
"""
NFX - Profilowanie jakosci danych katalogu Nike (Global_Nike.csv)
-----------------------------------------------------------------
Skanuje surowy plik CSV w trybie strumieniowym (chunki), liczy metryki
jakosci danych wymagane w rozdziale "Analiza jakosci danych" i jednoczesnie
buduje odchudzony ekstrakt na poziomie PRODUKT x KRAJ (1 wiersz = 1 style_color
w 1 kraju w 1 dacie snapshotu), ktory jest wlasciwa ziarnistoscia dla FACT_Prices.

Uruchomienie:
    python profile_nike.py --csv ../../Global_Nike.csv --outdir .

Wyniki:
    data_quality_report.md     - raport jakosci danych (liczby rzeczywiste)
    profile_summary.json       - surowe metryki (do testow / dokumentacji)
    nike_product_country.csv   - deduplikowany ekstrakt PRODUKT x KRAJ (wejscie ETL)
    currency_coverage.csv      - pokrycie walut katalogu vs NBP A/B
"""
import argparse, json, os, sys, io
from collections import Counter, defaultdict
import pandas as pd

# Kolumny istotne dla hurtowni (reszta z 35 kolumn CSV jest ignorowana w profilu)
USECOLS = [
    "snapshot_date", "country_code", "product_name", "model_number", "currency",
    "price_local", "sale_price_local", "gender_segment", "category", "subcategory",
    "product_id", "sku", "style_color", "color_name", "discount_pct", "in_stock",
    "available", "availability_level",
]

CHUNK = 200_000


def to_float(s):
    try:
        return float(s)
    except (TypeError, ValueError):
        return None


def main():
    ap = argparse.ArgumentParser()
    ap.add_argument("--csv", required=True)
    ap.add_argument("--outdir", default=".")
    ap.add_argument("--max-products-extract", type=int, default=0,
                    help="0 = bez limitu; inaczej obetnij ekstrakt do N wierszy product-country")
    args = ap.parse_args()

    os.makedirs(args.outdir, exist_ok=True)

    total_rows = 0
    country_ctr = Counter()
    currency_ctr = Counter()
    category_ctr = Counter()
    subcategory_ctr = Counter()
    gender_ctr = Counter()
    snapshot_ctr = Counter()
    avail_ctr = Counter()

    null_counts = Counter()      # braki w polach kluczowych
    price_le_zero = 0
    price_nonnumeric = 0
    sale_gt_price = 0

    # cross-country overlap: style_color -> set(country)
    sc_countries = defaultdict(set)

    # deduplikacja do poziomu (style_color, country_code, snapshot_date)
    # przechowujemy pierwszy napotkany komplet atrybutow + cene
    product_country = {}

    key_fields = ["sku", "style_color", "model_number", "price_local",
                  "currency", "country_code", "category", "product_name"]

    reader = pd.read_csv(
        args.csv, usecols=USECOLS, dtype=str, chunksize=CHUNK,
        keep_default_na=False, na_values=[""]
    )

    for ci, chunk in enumerate(reader):
        n = len(chunk)
        total_rows += n

        for col in key_fields:
            null_counts[col] += int(chunk[col].isna().sum())

        country_ctr.update(chunk["country_code"].dropna().tolist())
        currency_ctr.update(chunk["currency"].dropna().tolist())
        category_ctr.update(chunk["category"].dropna().tolist())
        subcategory_ctr.update(chunk["subcategory"].dropna().tolist())
        gender_ctr.update(chunk["gender_segment"].dropna().tolist())
        snapshot_ctr.update(chunk["snapshot_date"].dropna().tolist())
        avail_ctr.update(chunk["availability_level"].dropna().tolist())

        # price quality + dedup w jednym przebiegu
        for row in chunk.itertuples(index=False):
            d = row._asdict()
            sc = d.get("style_color")
            cc = d.get("country_code")
            sd = d.get("snapshot_date")
            p = to_float(d.get("price_local"))
            sp = to_float(d.get("sale_price_local"))

            if d.get("price_local") is None:
                pass  # liczone w null_counts
            elif p is None:
                price_nonnumeric += 1
            elif p <= 0:
                price_le_zero += 1
            if p is not None and sp is not None and sp > p:
                sale_gt_price += 1

            if sc and cc:
                sc_countries[sc].add(cc)
                key = (sc, cc, sd)
                if key not in product_country:
                    product_country[key] = {
                        "style_color": sc,
                        "country_code": cc,
                        "snapshot_date": sd,
                        "model_number": d.get("model_number"),
                        "product_name": d.get("product_name"),
                        "color_name": d.get("color_name"),
                        "gender_segment": d.get("gender_segment"),
                        "category": d.get("category"),
                        "subcategory": d.get("subcategory"),
                        "currency": d.get("currency"),
                        "price_local": p,
                        "sale_price_local": sp,
                        "discount_pct": to_float(d.get("discount_pct")),
                        "in_stock": d.get("in_stock"),
                        "availability_level": d.get("availability_level"),
                    }

        print(f"  chunk {ci+1}: rows so far = {total_rows:,}", file=sys.stderr)

    # ---- metryki pochodne ----
    distinct_style_color = len(sc_countries)
    distinct_country = len(country_ctr)
    distinct_currency = len(currency_ctr)

    countries_per_sc = Counter(len(v) for v in sc_countries.values())
    multi_country = sum(1 for v in sc_countries.values() if len(v) >= 2)
    multi_country_ge5 = sum(1 for v in sc_countries.values() if len(v) >= 5)
    max_countries = max((len(v) for v in sc_countries.values()), default=0)

    pc_rows = list(product_country.values())
    # duplikaty na poziomie produkt x kraj x data nie istnieja (deduplikacja),
    # ale policzmy ile wierszy CSV "zwinelismy"
    dedup_rows = len(pc_rows)

    # ---- pokrycie walut vs NBP (A i B) ----
    nbp_codes = load_nbp_codes(args.outdir)
    coverage = []
    for code, cnt in sorted(currency_ctr.items(), key=lambda x: -x[1]):
        tab = nbp_codes.get(code, "BRAK")
        coverage.append({"currency": code, "rows": cnt,
                         "nbp_table": tab,
                         "covered": tab in ("A", "B")})
    cov_df = pd.DataFrame(coverage)
    cov_df.to_csv(os.path.join(args.outdir, "currency_coverage.csv"),
                  index=False, encoding="utf-8")

    uncovered = [c["currency"] for c in coverage if not c["covered"]]

    # ---- zapis ekstraktu product-country ----
    pc_df = pd.DataFrame(pc_rows)
    if args.max_products_extract and len(pc_df) > args.max_products_extract:
        pc_df = pc_df.sort_values(["style_color", "country_code"]).head(args.max_products_extract)
    pc_path = os.path.join(args.outdir, "nike_product_country.csv")
    pc_df.to_csv(pc_path, index=False, encoding="utf-8")

    # ---- JSON summary ----
    summary = {
        "source_file": os.path.abspath(args.csv),
        "total_raw_rows": total_rows,
        "distinct_country": distinct_country,
        "distinct_currency": distinct_currency,
        "distinct_style_color": distinct_style_color,
        "product_country_grain_rows": dedup_rows,
        "snapshot_dates": dict(snapshot_ctr),
        "categories": dict(category_ctr),
        "gender_segments": dict(gender_ctr),
        "top_subcategories": dict(Counter(subcategory_ctr).most_common(20)),
        "country_row_counts": dict(country_ctr),
        "currency_row_counts": dict(currency_ctr),
        "availability_levels": dict(avail_ctr),
        "null_counts_key_fields": dict(null_counts),
        "price_le_zero": price_le_zero,
        "price_nonnumeric": price_nonnumeric,
        "sale_gt_price": sale_gt_price,
        "products_in_2plus_countries": multi_country,
        "products_in_5plus_countries": multi_country_ge5,
        "max_countries_per_product": max_countries,
        "countries_per_product_hist": {str(k): v for k, v in sorted(countries_per_sc.items())},
        "nbp_currency_coverage": {
            "catalogue_currencies": distinct_currency,
            "uncovered_by_nbp_AB": uncovered,
            "uncovered_count": len(uncovered),
        },
    }
    with io.open(os.path.join(args.outdir, "profile_summary.json"), "w", encoding="utf-8") as f:
        json.dump(summary, f, ensure_ascii=False, indent=2)

    write_report(args.outdir, summary, coverage)
    print("OK - profil zapisany.", file=sys.stderr)


def load_nbp_codes(outdir):
    """Wczytaj zbior kodow walut NBP (A+B) jesli istnieje plik z fetchera."""
    path = os.path.join(outdir, "..", "02_etl", "nbp_currency_codes.json")
    if os.path.exists(path):
        with io.open(path, encoding="utf-8") as f:
            return json.load(f)
    return {}


def write_report(outdir, s, coverage):
    L = []
    a = L.append
    a("# NFX — Analiza jakości danych (katalog Nike)\n")
    a(f"_Plik źródłowy:_ `Global_Nike.csv`  ")
    a(f"_Wiersze surowe (z nagłówkiem−1):_ **{s['total_raw_rows']:,}**  ")
    a(f"_Data wygenerowania profilu:_ skrypt `profile_nike.py`\n")

    a("## 1. Przegląd zbioru\n")
    a("| Metryka | Wartość |")
    a("|---|---|")
    a(f"| Wiersze surowe (ziarno: produkt × kraj × **rozmiar**) | {s['total_raw_rows']:,} |")
    a(f"| Po deduplikacji do ziarna **produkt × kraj × data** | {s['product_country_grain_rows']:,} |")
    a(f"| Różne kraje (`country_code`) | {s['distinct_country']} |")
    a(f"| Różne waluty (`currency`) | {s['distinct_currency']} |")
    a(f"| Różne produkty (`style_color`) | {s['distinct_style_color']:,} |")
    a(f"| Daty snapshotu | {', '.join(s['snapshot_dates'].keys())} |")
    a("")

    a("## 2. Wykonalność arbitrażu (kluczowe!)\n")
    a("Arbitraż wymaga, by **ten sam produkt** był sprzedawany w **wielu krajach**. ")
    a("Klucz naturalny produktu = `style_color` (model + kolorystyka).\n")
    a("| Metryka | Wartość |")
    a("|---|---|")
    a(f"| Produkty obecne w ≥2 krajach | {s['products_in_2plus_countries']:,} |")
    a(f"| Produkty obecne w ≥5 krajach | {s['products_in_5plus_countries']:,} |")
    a(f"| Maks. liczba krajów dla jednego produktu | {s['max_countries_per_product']} |")
    a("")

    a("## 3. Braki w polach kluczowych (NULL/puste)\n")
    a("| Pole | Liczba braków |")
    a("|---|---|")
    for k, v in s["null_counts_key_fields"].items():
        a(f"| `{k}` | {v:,} |")
    a("")

    a("## 4. Poprawność cen\n")
    a("| Problem | Liczba wierszy | Decyzja ETL |")
    a("|---|---|---|")
    a(f"| `price_local` ≤ 0 | {s['price_le_zero']:,} | odrzuć → `staging.error_log` |")
    a(f"| `price_local` nienumeryczne | {s['price_nonnumeric']:,} | odrzuć → `staging.error_log` |")
    a(f"| `price_local` NULL/puste | {s['null_counts_key_fields'].get('price_local',0):,} | odrzuć → `staging.error_log` |")
    a(f"| `sale_price_local` > `price_local` | {s['sale_gt_price']:,} | flaga ostrzeżenia (nie odrzucaj) |")
    a("")

    a("## 5. Pokrycie walut przez NBP (tabele A/B)\n")
    unc = s["nbp_currency_coverage"]["uncovered_by_nbp_AB"]
    a(f"Walut w katalogu: **{s['distinct_currency']}**. ")
    a(f"Niepokrytych przez NBP A/B: **{len(unc)}** "
      f"({', '.join(unc) if unc else 'brak — wszystkie pokryte'}).\n")
    a("| Waluta | Wiersze | Tabela NBP | Pokryta |")
    a("|---|---|---|---|")
    for c in coverage:
        a(f"| {c['currency']} | {c['rows']:,} | {c['nbp_table']} | {'✅' if c['covered'] else '❌'} |")
    a("")

    a("## 6. Rozkład krajów (wiersze surowe)\n")
    a("| Kraj | Wiersze |")
    a("|---|---|")
    for cc, cnt in sorted(s["country_row_counts"].items(), key=lambda x: -x[1]):
        a(f"| {cc} | {cnt:,} |")
    a("")

    a("## 7. Kategorie i płeć\n")
    a("**Kategorie:** " + ", ".join(f"{k} ({v:,})" for k, v in s["categories"].items()) + "\n")
    a("**Płeć:** " + ", ".join(f"{k} ({v:,})" for k, v in s["gender_segments"].items()) + "\n")

    a("## 8. Wnioski → reguły ETL i przypadki testowe\n")
    a("| # | Problem | Decyzja | Test |")
    a("|---|---|---|---|")
    a("| 1 | Ziarno per rozmiar — cena powielona | Deduplikacja do produkt×kraj×data (MAX/MIN identyczne) | T-ETL-02 |")
    a("| 2 | Ceny ≤ 0 / nienumeryczne / NULL | Odrzucenie do `error_log` z `reject_reason` | T-ETL-03 |")
    a("| 3 | Waluty spoza NBP A/B | Mapowanie / oznaczenie `nbp_table_type`; brak kursu → brak `price_pln` | T-ETL-04 |")
    a("| 4 | Klucz naturalny produktu | `style_color` (model+kolor), nie UUID `sku` | T-DW-01 |")
    a("| 5 | `sale_price_local`>`price_local` | Flaga ostrzegawcza | T-DQ-05 |")

    with io.open(os.path.join(outdir, "data_quality_report.md"), "w", encoding="utf-8") as f:
        f.write("\n".join(L))


if __name__ == "__main__":
    main()
