# NFX – Nike Foreign Exchange · Hurtownia danych (HiDBI)

Hurtownia łącząca globalny katalog cen Nike z kursami NBP w celu wykrywania
**okazji arbitrażu cenowego** między rynkami. Repozytorium zawiera kompletne,
**uruchomione i przetestowane** rozwiązanie: DDL, ETL, warstwę BI, raporty, testy i dokumentację.

## Stan realizacji (zrobione automatycznie)
| Etap | Status | Dowód |
|---|---|---|
| Analiza jakości danych | ✅ | `05_data_profiling/data_quality_report.md` (na 1,45 mln wierszy) |
| Pobranie kursów NBP (A/B/C, 93-dni) | ✅ | `02_etl/nbp_fetch.py`, `stg_fx_rates.csv` (7 708 w.) |
| Model fizyczny (gwiazda) + deploy | ✅ | `01_sql/01..08`, baza `NFX_DW` na SQL Server 2019 |
| ETL: staging→wymiary→fakty (SCD2, dedup, PLN) | ✅ | `02_etl/run_etl.py`, 183 607 wierszy faktów |
| Warstwa OLAP/BI (widoki, DAX, hierarchie) | ✅ | `01_sql/08_*`, `04_powerbi/*` |
| Raporty (3 strony) w PDF | ✅ | `07_reports/report_*.pdf` |
| Testy funkcjonalne | ✅ 14/14 PASS | `06_tests/test_results.md` |
| Dokumentacja + diagramy | ✅ | `08_docs/*` |

> Czego **nie** zautomatyzowano (wymaga rąk ludzkich): złożenie pliku `.pbix` w
> Power BI Desktop, zbudowanie binarnych `.dtsx` w Visual Studio, uruchomienie
> usługi SQL Server Agent. Szczegóły i instrukcja: **`NFX_Plan_Dokonczenia.md`**.

## Wymagania
- SQL Server 2019+ (Developer/Express) z uruchomionym silnikiem; `sqlcmd` + ODBC Driver 17.
- Python 3.11 + pakiety: `pip install -r requirements.txt`.
- (do dokończenia) Power BI Desktop, Visual Studio + rozszerzenie SSIS.

## Szybki start (od zera)
```powershell
# 1. Wdróż schemat hurtowni (reset + 01..08)
powershell -File 01_sql\deploy_all.ps1 -Reset

# 2. Pobierz kursy NBP (inicjalizacja: całe 2026 do dziś, tabele A/B/C)
python 02_etl\nbp_fetch.py --start 2026-01-01 --end 2026-06-13 --tables A B C --outdir 02_etl

# 3. (jeśli masz Global_Nike.csv) wygeneruj ekstrakt produkt×kraj + raport jakości
python 05_data_profiling\profile_nike.py --csv ..\Global_Nike.csv --outdir 05_data_profiling
#    bez pliku źródłowego użyj próbki:  sample_data\nike_product_country_sample.csv

# 4. Uruchom ETL (inicjalizacja)
python 02_etl\run_etl.py --mode initial
#    kolejna iteracja:  python 02_etl\run_etl.py --mode incremental

# 5. Testy funkcjonalne (14/14 PASS)
python 06_tests\run_tests.py

# 6. Raporty PDF
python 07_reports\report_generator.py

# 7. Diagramy do dokumentacji
python 08_docs\generate_diagrams.py
```
Połączenie z bazą konfiguruje `02_etl/config.json` (domyślnie `localhost`, Windows Auth).

## Struktura
```
01_sql/         DDL, procedury ETL, widoki BI, joby Agent, deploy_all.ps1
02_etl/         nbp_fetch.py, run_etl.py, db_util.py, config.json, dane FX
03_ssis/        NBP_ScriptTask.cs (C#), SSIS_build_guide.md
04_powerbi/     measures.dax, powerquery_sources.m, model_description.md, powerbi_build_guide.md, NFX_theme.json
05_data_profiling/ profile_nike.py, data_quality_report.md, ekstrakt produkt×kraj
06_tests/       run_tests.py, functional_tests.sql, test_results.md/json
07_reports/     report_generator.py, report_1/2/3.pdf, NFX_Reports_ALL.pdf, podglądy
08_docs/        NFX_Dokumentacja_Finalna.md, diagramy (architektura + model fizyczny)
sample_data/    próbka katalogu (bez danych źródłowych)
_evidence/      logi i zrzuty kontrolne
```

## Dane źródłowe
`Global_Nike.csv` (~881 MB, Kaggle) **nie wchodzi** do paczki oddawczej. Pobierz z
`kaggle.com/datasets/bsthere/nike-global-catalogue-2026`. Do demonstracji wystarcza
`sample_data/nike_product_country_sample.csv`.
