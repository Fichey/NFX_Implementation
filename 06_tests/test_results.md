# NFX — Wyniki testów funkcjonalnych

_Wygenerowano:_ 2026-06-15 02:28  ·  _Środowisko:_ SQL Server 2019 Developer, baza `NFX_DW`  ·  _Uruchomienie:_ `python 06_tests/run_tests.py`

## Podsumowanie: **14/14 PASS**

| # | Warstwa | Cel | Status | Potwierdzenie (wartość rzeczywista) |
|---|---|---|---|---|
| T-ETL-01 | ETL / CSV | Kompletnosc ekstrakcji: liczba wierszy w staging = liczba rekordow zaladowanego pliku | ✅ PASS | `staging=4,505 -> probka (pelny=175917 / probka=4505)` |
| T-ETL-02 | ETL / transformacja | Brak gubienia danych: kazdy poprawny wiersz staging ma odpowiednik w FACT_Prices | ✅ PASS | `valid_staging=4,505 dopasowane_w_fakcie=4,505; odrzucone=0` |
| T-ETL-03 | ETL / walidacja | Reguła jakości: ceny <=0 odrzucone do error_log, brak w fakcie | ✅ PASS | `zle_w_fakcie=0; odrzuty_price=0/0` |
| T-ETL-04 | ETL / NBP | Pobranie kursow: tabela A pokrywa >=32 walut, brak NULL w mid | ✅ PASS | `walut_A=32; null_mid_A=0` |
| T-ETL-05 | ETL / limit 93 dni | Zapytanie o 180 dni dzielone na segmenty <=93 dni (limit NBP, brak 400) | ✅ PASS | `segmentow=2, max_dni=90` |
| T-DW-01 | Hurtownia / SCD2 | DIM_Product SCD Typ 2: zmiana atrybutu zamyka stary rekord i tworzy nowy | ✅ PASS | `przed=1 po=2; zamkniete=1; nowy_aktualny=1` |
| T-DW-02 | Hurtownia / przeliczenie | Poprawnosc transformacji: price_pln = local_price * kurs_mid (USD) | ✅ PASS | `kurs_USD=3.727000; max_odchylenie=2.999999992425728e-05` |
| T-DW-03 | Hurtownia / dedup FX | Deduplikacja FX: brak duplikatow (data+waluta+tabela) | ✅ PASS | `count=7,708 distinct=7,708` |
| T-DW-04 | Hurtownia / integralnosc | Integralnosc referencyjna: brak osieroconych kluczy obcych w FACT_Prices | ✅ PASS | `osierocone=0` |
| T-BI-01 | BI / miara marzy | Poprawnosc miary: marza z widoku BI = reczne (max-min)/min z faktow | ✅ PASS | `BI=894.5% reczne=894.5%` |
| T-BI-02 | BI / outliery | Reguła outlierow: widok arbitrazu nie zawiera cen-sentineli (>50000 PLN) | ✅ PASS | `outliery_w_widoku=0` |
| T-XL-01 | Spojnosc (cross-layer) | Ta sama cena na kazdym etapie: plik -> staging -> fakt -> widok BI | ✅ PASS | `plik=119.99 staging=119.99 fakt=119.99 BI=119.99` |
| T-INC-01 | Scenariusz / incremental | Kolejna iteracja: ponowne ladowanie FX nie tworzy duplikatow (idempotencja) | ✅ PASS | `przed=7,708 po=7,708 przyrost=0` |
| T-E2E-01 | End-to-end | Calosciowe dzialanie: ETL SUCCESS i warstwa BI zwraca sensowne KPI | ✅ PASS | `status=SUCCESS; produkty=29,249; rynki=45; okazje>20%=9,227` |

---
## Szczegóły testów

### T-ETL-01 — ETL / CSV
- **(1) Cel:** Kompletnosc ekstrakcji: liczba wierszy w staging = liczba rekordow zaladowanego pliku
- **(2) Kroki:** COUNT(*) staging vs liczba rekordow CSV (pelny lub probka)
- **(3) Oczekiwany wynik:** rownosc z jednym ze zrodel
- **(4) Potwierdzenie:** `staging=4,505 -> probka (pelny=175917 / probka=4505)` → **PASS**

### T-ETL-02 — ETL / transformacja
- **(1) Cel:** Brak gubienia danych: kazdy poprawny wiersz staging ma odpowiednik w FACT_Prices
- **(2) Kroki:** valid(staging) = dopasowane do FACT_Prices; niepoprawne -> error_log
- **(3) Oczekiwany wynik:** kazdy poprawny wiersz obecny w fakcie
- **(4) Potwierdzenie:** `valid_staging=4,505 dopasowane_w_fakcie=4,505; odrzucone=0` → **PASS**

### T-ETL-03 — ETL / walidacja
- **(1) Cel:** Reguła jakości: ceny <=0 odrzucone do error_log, brak w fakcie
- **(2) Kroki:** FACT_Prices WHERE local_price<=0  (oczek. 0) oraz error_log z powodem 'price%'
- **(3) Oczekiwany wynik:** 0 zlych cen w fakcie; wszystkie odrzuty opisane
- **(4) Potwierdzenie:** `zle_w_fakcie=0; odrzuty_price=0/0` → **PASS**

### T-ETL-04 — ETL / NBP
- **(1) Cel:** Pobranie kursow: tabela A pokrywa >=32 walut, brak NULL w mid
- **(2) Kroki:** DISTINCT currency_key oraz NULL mid w FACT_ExchangeRates (table_type='A')
- **(3) Oczekiwany wynik:** >=32 walut, 0 NULL mid
- **(4) Potwierdzenie:** `walut_A=32; null_mid_A=0` → **PASS**

### T-ETL-05 — ETL / limit 93 dni
- **(1) Cel:** Zapytanie o 180 dni dzielone na segmenty <=93 dni (limit NBP, brak 400)
- **(2) Kroki:** nbp_fetch.daterange_segments(2026-01-01, 2026-06-29)
- **(3) Oczekiwany wynik:** >=2 segmenty, kazdy <=93 dni
- **(4) Potwierdzenie:** `segmentow=2, max_dni=90` → **PASS**

### T-DW-01 — Hurtownia / SCD2
- **(1) Cel:** DIM_Product SCD Typ 2: zmiana atrybutu zamyka stary rekord i tworzy nowy
- **(2) Kroki:** zmien color_name dla 'CW7635-991', wywolaj usp_LoadDimProduct_SCD2 (load_date=jutro)
- **(3) Oczekiwany wynik:** stary is_current=0+valid_to; nowy is_current=1 z nowa wartoscia; +1 wiersz
- **(4) Potwierdzenie:** `przed=1 po=2; zamkniete=1; nowy_aktualny=1` → **PASS**

### T-DW-02 — Hurtownia / przeliczenie
- **(1) Cel:** Poprawnosc transformacji: price_pln = local_price * kurs_mid (USD)
- **(2) Kroki:** MAX(ABS(price_pln - local_price*kurs_USD)) dla wszystkich rekordow USD
- **(3) Oczekiwany wynik:** odchylenie <= 0,001 PLN (zaokraglenie)
- **(4) Potwierdzenie:** `kurs_USD=3.727000; max_odchylenie=2.999999992425728e-05` → **PASS**

### T-DW-03 — Hurtownia / dedup FX
- **(1) Cel:** Deduplikacja FX: brak duplikatow (data+waluta+tabela)
- **(2) Kroki:** COUNT(*) vs COUNT(DISTINCT effective_date,currency_key,table_type)
- **(3) Oczekiwany wynik:** rownosc
- **(4) Potwierdzenie:** `count=7,708 distinct=7,708` → **PASS**

### T-DW-04 — Hurtownia / integralnosc
- **(1) Cel:** Integralnosc referencyjna: brak osieroconych kluczy obcych w FACT_Prices
- **(2) Kroki:** FACT_Prices bez dopasowania w ktoryms z 5 wymiarow
- **(3) Oczekiwany wynik:** 0 osieroconych wierszy
- **(4) Potwierdzenie:** `osierocone=0` → **PASS**

### T-BI-01 — BI / miara marzy
- **(1) Cel:** Poprawnosc miary: marza z widoku BI = reczne (max-min)/min z faktow
- **(2) Kroki:** porownaj bi.v_product_arbitrage.margin_pct dla 'BA5957-077' z obliczeniem recznym
- **(3) Oczekiwany wynik:** zgodnosc <= 0,5 p.p.
- **(4) Potwierdzenie:** `BI=894.5% reczne=894.5%` → **PASS**

### T-BI-02 — BI / outliery
- **(1) Cel:** Reguła outlierow: widok arbitrazu nie zawiera cen-sentineli (>50000 PLN)
- **(2) Kroki:** bi.v_product_arbitrage WHERE max_price_pln>50000
- **(3) Oczekiwany wynik:** 0 wierszy
- **(4) Potwierdzenie:** `outliery_w_widoku=0` → **PASS**

### T-XL-01 — Spojnosc (cross-layer)
- **(1) Cel:** Ta sama cena na kazdym etapie: plik -> staging -> fakt -> widok BI
- **(2) Kroki:** sledz CW7635-991/AT przez warstwy
- **(3) Oczekiwany wynik:** identyczna cena lokalna
- **(4) Potwierdzenie:** `plik=119.99 staging=119.99 fakt=119.99 BI=119.99` → **PASS**

### T-INC-01 — Scenariusz / incremental
- **(1) Cel:** Kolejna iteracja: ponowne ladowanie FX nie tworzy duplikatow (idempotencja)
- **(2) Kroki:** ponowne EXEC usp_LoadFactExchangeRates na tym samym staging (w transakcji)
- **(3) Oczekiwany wynik:** przyrost = 0 wierszy
- **(4) Potwierdzenie:** `przed=7,708 po=7,708 przyrost=0` → **PASS**

### T-E2E-01 — End-to-end
- **(1) Cel:** Calosciowe dzialanie: ETL SUCCESS i warstwa BI zwraca sensowne KPI
- **(2) Kroki:** etl_run_log (ostatni przebieg) + bi.v_kpi_summary
- **(3) Oczekiwany wynik:** status SUCCESS, produkty>0, okazje>0
- **(4) Potwierdzenie:** `status=SUCCESS; produkty=29,249; rynki=45; okazje>20%=9,227` → **PASS**


## Scenariusze ładowania
- **Inicjalizacja (INITIAL):** `python 02_etl/run_etl.py --mode initial` — puste tabele → pełne załadowanie (log: `staging.etl_run_log`).
- **Kolejna iteracja (INCREMENTAL):** `python 02_etl/run_etl.py --mode incremental` — deduplikacja FX (T-INC-01) chroni przed duplikatami; katalog ładowany ze SCD2 (T-DW-01).

## Dowody dodatkowe
- Log ETL: `_evidence/etl_run_*.txt` oraz tabela `staging.etl_run_log`.
- Log pobierania NBP (segmentacja 93 dni): `02_etl/nbp_fetch_log.txt`.
- Podglądy raportów: `07_reports/report_*.png`.