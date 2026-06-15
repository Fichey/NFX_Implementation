# NFX — Analiza jakości danych (katalog Nike)

_Plik źródłowy:_ `Global_Nike.csv`  
_Wiersze surowe (z nagłówkiem−1):_ **1,447,795**  
_Data wygenerowania profilu:_ skrypt `profile_nike.py`

## 1. Przegląd zbioru

| Metryka | Wartość |
|---|---|
| Wiersze surowe (ziarno: produkt × kraj × **rozmiar**) | 1,447,795 |
| Po deduplikacji do ziarna **produkt × kraj × data** | 175,917 |
| Różne kraje (`country_code`) | 45 |
| Różne waluty (`currency`) | 29 |
| Różne produkty (`style_color`) | 29,249 |
| Daty snapshotu | 2026-03-19 |

## 2. Wykonalność arbitrażu (kluczowe!)

Arbitraż wymaga, by **ten sam produkt** był sprzedawany w **wielu krajach**. 
Klucz naturalny produktu = `style_color` (model + kolorystyka).

| Metryka | Wartość |
|---|---|
| Produkty obecne w ≥2 krajach | 11,772 |
| Produkty obecne w ≥5 krajach | 9,049 |
| Maks. liczba krajów dla jednego produktu | 40 |

## 3. Braki w polach kluczowych (NULL/puste)

| Pole | Liczba braków |
|---|---|
| `sku` | 2 |
| `style_color` | 0 |
| `model_number` | 0 |
| `price_local` | 0 |
| `currency` | 0 |
| `country_code` | 0 |
| `category` | 0 |
| `product_name` | 0 |

## 4. Poprawność cen

| Problem | Liczba wierszy | Decyzja ETL |
|---|---|---|
| `price_local` ≤ 0 | 18 | odrzuć → `staging.error_log` |
| `price_local` nienumeryczne | 0 | odrzuć → `staging.error_log` |
| `price_local` NULL/puste | 0 | odrzuć → `staging.error_log` |
| `sale_price_local` > `price_local` | 210,687 | flaga ostrzeżenia (nie odrzucaj) |

## 5. Pokrycie walut przez NBP (tabele A/B)

Walut w katalogu: **29**. 
Niepokrytych przez NBP A/B: **2** (PLN, BGN).

| Waluta | Wiersze | Tabela NBP | Pokryta |
|---|---|---|---|
| EUR | 719,260 | A | ✅ |
| USD | 69,949 | A | ✅ |
| JPY | 43,306 | A | ✅ |
| GBP | 39,765 | A | ✅ |
| DKK | 39,362 | A | ✅ |
| PLN | 39,186 | BRAK | ❌ |
| SEK | 38,519 | A | ✅ |
| CHF | 38,088 | A | ✅ |
| CNY | 37,547 | A | ✅ |
| ILS | 36,874 | A | ✅ |
| RON | 36,811 | A | ✅ |
| ZAR | 36,663 | A | ✅ |
| CAD | 33,730 | A | ✅ |
| TRY | 30,034 | A | ✅ |
| PHP | 22,967 | A | ✅ |
| SGD | 22,967 | A | ✅ |
| MYR | 22,602 | A | ✅ |
| IDR | 22,499 | A | ✅ |
| THB | 21,929 | A | ✅ |
| TWD | 21,036 | B | ✅ |
| VND | 20,115 | B | ✅ |
| MXN | 19,569 | A | ✅ |
| KRW | 15,636 | A | ✅ |
| NOK | 15,363 | A | ✅ |
| INR | 2,038 | A | ✅ |
| NZD | 1,501 | A | ✅ |
| BGN | 244 | BRAK | ❌ |
| AUD | 230 | A | ✅ |
| EGP | 5 | B | ✅ |

## 6. Rozkład krajów (wiersze surowe)

| Kraj | Wiersze |
|---|---|
| US | 69,949 |
| LU | 45,053 |
| IE | 44,064 |
| JP | 43,306 |
| BE | 43,090 |
| NL | 42,622 |
| SI | 42,065 |
| AT | 41,197 |
| PT | 40,144 |
| IT | 39,953 |
| GR | 39,949 |
| GB | 39,765 |
| FR | 39,731 |
| DE | 39,625 |
| DK | 39,362 |
| CZ | 39,269 |
| PL | 39,186 |
| HU | 38,790 |
| SE | 38,519 |
| CH | 38,088 |
| ES | 37,960 |
| HR | 37,906 |
| CN | 37,547 |
| IL | 36,874 |
| RO | 36,811 |
| SK | 36,742 |
| ZA | 36,663 |
| FI | 36,443 |
| BG | 34,901 |
| CA | 33,730 |
| TR | 30,034 |
| PH | 22,967 |
| SG | 22,967 |
| MY | 22,602 |
| ID | 22,499 |
| TH | 21,929 |
| TW | 21,036 |
| VN | 20,115 |
| MX | 19,569 |
| KR | 15,636 |
| NO | 15,363 |
| IN | 2,038 |
| NZ | 1,501 |
| AU | 230 |
| EG | 5 |

## 7. Kategorie i płeć

**Kategorie:** APPAREL (696,577), EQUIPMENT (26,389), FOOTWEAR (724,811), DIGITAL_GIFT_CARD (2), PHYSICAL_GIFT_CARD (16)

**Płeć:** MEN (579,987), WOMEN (373,417), MEN|WOMEN (231,852), BOYS|GIRLS (192,882), BOYS (27,176), MEN|BOYS|WOMEN|GIRLS (2,629), GIRLS (32,659), MEN|WOMEN|GIRLS (7), WOMEN|GIRLS (253), MEN|BOYS|GIRLS (14), BOYS|WOMEN|GIRLS (110), GIRLS|BOYS (30), WOMEN|MEN (32)

## 8. Wnioski → reguły ETL i przypadki testowe

| # | Problem | Decyzja | Test |
|---|---|---|---|
| 1 | Ziarno per rozmiar — cena powielona | Deduplikacja do produkt×kraj×data (MAX/MIN identyczne) | T-ETL-02 |
| 2 | Ceny ≤ 0 / nienumeryczne / NULL | Odrzucenie do `error_log` z `reject_reason` | T-ETL-03 |
| 3 | Waluty spoza NBP A/B | Mapowanie / oznaczenie `nbp_table_type`; brak kursu → brak `price_pln` | T-ETL-04 |
| 4 | Klucz naturalny produktu | `style_color` (model+kolor), nie UUID `sku` | T-DW-01 |
| 5 | `sale_price_local`>`price_local` | Flaga ostrzegawcza | T-DQ-05 |