/* =====================================================================
   NFX – Testy funkcjonalne w czystym SQL (do uruchomienia w SSMS)
   Odpowiednik 06_tests/run_tests.py. Kazde zapytanie zwraca kolumne
   [oczekiwany] i [rzeczywisty]/[status]. Uruchom na bazie NFX_DW po ETL.
   ===================================================================== */
USE NFX_DW;
SET NOCOUNT ON;

PRINT '== T-ETL-02: staging = fakt + odrzucone ==';
SELECT (SELECT COUNT(*) FROM staging.stg_nike_prices) AS staging,
       (SELECT COUNT(*) FROM dw.FACT_Prices)          AS fakt,
       (SELECT COUNT(*) FROM staging.error_log)        AS odrzucone,
       CASE WHEN (SELECT COUNT(*) FROM staging.stg_nike_prices)
                 = (SELECT COUNT(*) FROM dw.FACT_Prices)+(SELECT COUNT(*) FROM staging.error_log)
            THEN 'PASS' ELSE 'FAIL' END AS status;

PRINT '== T-ETL-03: brak cen <=0 w fakcie ==';
SELECT COUNT(*) AS zle_ceny_w_fakcie,
       CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END status
FROM dw.FACT_Prices WHERE local_price <= 0;

PRINT '== T-ETL-04: tabela A >=32 walut, brak NULL mid ==';
SELECT COUNT(DISTINCT currency_key) AS walut_A,
       SUM(CASE WHEN mid_rate IS NULL THEN 1 ELSE 0 END) AS null_mid,
       CASE WHEN COUNT(DISTINCT currency_key)>=32 AND SUM(CASE WHEN mid_rate IS NULL THEN 1 ELSE 0 END)=0
            THEN 'PASS' ELSE 'FAIL' END status
FROM dw.FACT_ExchangeRates WHERE table_type='A';

PRINT '== T-DW-02: price_pln = local_price * kurs_USD (snapshot) ==';
DECLARE @usd DECIMAL(18,6) = (
   SELECT TOP 1 f.mid_rate FROM dw.FACT_ExchangeRates f
   JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
   WHERE c.currency_code='USD' AND f.table_type='A'
     AND f.effective_date <= (SELECT MAX(full_date) FROM dw.DIM_Date d JOIN dw.FACT_Prices p ON p.date_key=d.date_key)
   ORDER BY f.effective_date DESC);
SELECT @usd AS kurs_USD,
       MAX(ABS(f.price_pln - f.local_price*@usd)) AS max_odchylenie,
       CASE WHEN MAX(ABS(f.price_pln - f.local_price*@usd)) <= 0.001 THEN 'PASS' ELSE 'FAIL' END status
FROM dw.FACT_Prices f JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
WHERE c.currency_code='USD';

PRINT '== T-DW-03: deduplikacja FX ==';
SELECT COUNT(*) AS cnt,
       (SELECT COUNT(*) FROM (SELECT DISTINCT effective_date,currency_key,table_type FROM dw.FACT_ExchangeRates) t) AS distinct_cnt,
       CASE WHEN COUNT(*)=(SELECT COUNT(*) FROM (SELECT DISTINCT effective_date,currency_key,table_type FROM dw.FACT_ExchangeRates) t)
            THEN 'PASS' ELSE 'FAIL' END status
FROM dw.FACT_ExchangeRates;

PRINT '== T-DW-04: integralnosc referencyjna FACT_Prices ==';
SELECT COUNT(*) AS osierocone,
       CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END status
FROM dw.FACT_Prices f
WHERE NOT EXISTS(SELECT 1 FROM dw.DIM_Product p   WHERE p.product_key=f.product_key)
   OR NOT EXISTS(SELECT 1 FROM dw.DIM_Geography g WHERE g.geo_key=f.geo_key)
   OR NOT EXISTS(SELECT 1 FROM dw.DIM_Currency c  WHERE c.currency_key=f.currency_key)
   OR NOT EXISTS(SELECT 1 FROM dw.DIM_Date d      WHERE d.date_key=f.date_key)
   OR NOT EXISTS(SELECT 1 FROM dw.DIM_Category k  WHERE k.category_key=f.category_key);

PRINT '== T-BI-02: brak outlierow w widoku arbitrazu ==';
SELECT COUNT(*) AS outliery,
       CASE WHEN COUNT(*)=0 THEN 'PASS' ELSE 'FAIL' END status
FROM bi.v_product_arbitrage WHERE max_price_pln > 50000;

PRINT '== T-XL-01: spojnosc cross-layer (NIKGD001K01-TYD / US) ==';
SELECT
  (SELECT price_local FROM staging.stg_nike_prices WHERE style_color='NIKGD001K01-TYD' AND country_code='US') AS staging,
  (SELECT f.local_price FROM dw.FACT_Prices f JOIN dw.DIM_Product p ON p.product_key=f.product_key
     JOIN dw.DIM_Geography g ON g.geo_key=f.geo_key WHERE p.style_color='NIKGD001K01-TYD' AND g.country_code='US') AS fakt,
  (SELECT local_price FROM bi.v_price_enriched WHERE style_color='NIKGD001K01-TYD' AND country_code='US') AS widok_bi;

PRINT '== T-E2E-01: ostatni przebieg ETL + KPI ==';
SELECT TOP 1 status AS etl_status, load_type, rows_in, rows_out, rows_rejected FROM staging.etl_run_log ORDER BY run_id DESC;
SELECT * FROM bi.v_kpi_summary;
