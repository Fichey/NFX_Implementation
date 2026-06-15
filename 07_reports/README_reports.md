# NFX — Przykładowe raporty biznesowe (opis realizacji)

Raporty wygenerowano **z realnych danych** w hurtowni `NFX_DW` (widoki `bi.*`)
skryptem [`report_generator.py`](report_generator.py). Odwzorowują 3 strony
mockupu Power BI. W docelowym wdrożeniu te same wizualizacje buduje się w Power BI
Desktop (model z `../04_powerbi`), a PDF eksportuje przez *File → Export → PDF*.

Pliki: `report_1_global_price_map.pdf`, `report_2_arbitrage.pdf`,
`report_3_fx_dashboard.pdf` oraz złączony `NFX_Reports_ALL.pdf` (podglądy `.png`).

---

## Strona 1 — Global Price Map
**Cel:** pokazać, jak cena jednego modelu (w PLN) różni się między 45 rynkami.
- Wybrany model: produkt FOOTWEAR o największej liczbie rynków (tu: *Nike Vomero 18 By You*, ~39 rynków).
- Ranking poziomy „cena PLN wg rynku" z kolorowaniem choropleth (czerwony = drogo, zielony = tanio); etykieta pokazuje też cenę lokalną i walutę.
- Karty KPI: najtańszy rynek, najdroższy rynek, spread (PLN), marża potencjalna.
- **Jak czytać:** kraje na dole (zielone) to rynki zakupu, na górze (czerwone) — rynki sprzedaży. Kraje strefy euro mają identyczną cenę PLN (ta sama cena EUR × ten sam kurs).
- *W Power BI:* wizual **Filled Map** (`country_name` = lokalizacja, `[Price PLN]` = kolor), slicery: kategoria / model / data, tooltip z kursem NBP.

## Strona 2 — Arbitrage Opportunities (raport główny)
**Cel:** wykryć produkty z największą różnicą cen między rynkami (potencjał arbitrażu).
- 4 KPI: maks. spread (PLN), maks. marża [%], liczba aktywnych okazji (>20%), waluta pod presją (największy spadek 30D).
- Tabela TOP-10 wg marży: model/SKU, kategoria, najtańszy/najdroższy rynek (kody krajów), spread PLN, pasek marży, status.
- **Formatowanie warunkowe:** marża >20% zielony, 10–20% bursztynowy, <10% czerwony.
- Panel boczny: kursy NBP (tab. A) — zmiana 30D.
- Wykres słupkowy: marża [%] TOP-10 SKU.
- **Jak czytać:** wiersz = produkt; „kup w kraju zielonym, sprzedaj w czerwonym". Marża = (cena_max − cena_min)/cena_min.

## Strona 3 — FX Dashboard
**Cel:** monitorować kursy NBP i ich zmienność (kontekst dla cen w PLN).
- KPI: najsilniejszy / najsłabszy trend 30D, pokrycie danych (liczba walut tab. A).
- Wykres liniowy: historia kursu mid (PLN) dla USD/EUR/GBP/CHF.
- Tabela: kurs bieżący vs 30 dni temu + Δ%.
- Heatmapa: zmienność miesięczna (współczynnik zmienności = stdev/avg) dla wybranych walut × miesiące.
- **Jak czytać:** rosnący kurs danej waluty → drożeją w PLN produkty z tego rynku → maleje atrakcyjność arbitrażowa zakupu tam.

---

### Uwaga o jakości danych w raportach
Ceny-sentinele (np. 100 000 NZD = placeholder „brak ceny") dają price_pln ≈ 217 tys.
i są **wykluczane** w widokach `bi.*` (próg 50 000 PLN). Surowe wartości pozostają
w `FACT_Prices` (audytowalność). Dzięki temu rankingi arbitrażu nie są zaburzone
przez 9 błędnych wierszy z rynku NZ.
