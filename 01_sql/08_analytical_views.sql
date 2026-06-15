/* =====================================================================
   NFX – Nike Foreign Exchange  |  08_analytical_views.sql
   Warstwa OLAP/BI (schemat bi) – widoki realizujace model biznesowy.
   To jest "warstwa raportowa" konsumowana przez Power BI (Import) oraz
   przez generator raportow PDF (07_reports).

   REGULA JAKOSCI (outliery): ceny katalogowe-sentinele (np. 100000 NZD =
   placeholder "brak ceny") daja price_pln ~217 tys. W danych jest czysta
   luka miedzy ~5 tys a ~100 tys PLN, dlatego prog odciecia = 50 000 PLN.
   Widoki arbitrazu wykluczaja takie wiersze; FACT_Prices przechowuje surowa
   wartosc (audytowalnosc).
   ===================================================================== */
USE NFX_DW;
GO
DECLARE @cap DECIMAL(14,4) = 50000;   -- (dokumentacyjnie) prog outliera price_pln
GO

/* ---------- bi.v_price_enriched : zdenormalizowany fakt cen + atrybuty ---------- */
IF OBJECT_ID('bi.v_price_enriched') IS NOT NULL DROP VIEW bi.v_price_enriched;
GO
CREATE VIEW bi.v_price_enriched AS
SELECT
    f.price_key,
    p.product_key, p.style_color, p.model_number, p.product_name, p.color_name,
    p.gender_segment,
    cat.category, cat.subcategory,
    g.geo_key, g.country_code, g.country_name, g.region, g.sub_region,
    c.currency_key, c.currency_code, c.currency_name, c.nbp_table_type,
    d.full_date AS snapshot_date, d.[year], d.[quarter], d.[month],
    f.local_price, f.sale_price_local, f.discount_pct,
    f.price_pln, f.price_eur, f.price_usd, f.in_stock,
    CAST(CASE WHEN f.price_pln > 50000 THEN 1 ELSE 0 END AS BIT) AS is_price_outlier
FROM dw.FACT_Prices f
JOIN dw.DIM_Product   p   ON p.product_key = f.product_key
JOIN dw.DIM_Geography g   ON g.geo_key      = f.geo_key
JOIN dw.DIM_Currency  c   ON c.currency_key = f.currency_key
JOIN dw.DIM_Date      d   ON d.date_key     = f.date_key
JOIN dw.DIM_Category  cat ON cat.category_key = f.category_key;
GO

/* ---------- bi.v_product_arbitrage : ranking arbitrazu per produkt ---------- */
IF OBJECT_ID('bi.v_product_arbitrage') IS NOT NULL DROP VIEW bi.v_product_arbitrage;
GO
CREATE VIEW bi.v_product_arbitrage AS
WITH base AS (   -- ceny sensowne (bez outlierow)
    SELECT f.product_key, f.geo_key, f.price_pln
    FROM dw.FACT_Prices f
    WHERE f.price_pln IS NOT NULL AND f.price_pln BETWEEN 1 AND 50000
),
agg AS (
    SELECT product_key,
           COUNT(DISTINCT geo_key) AS n_markets,
           MIN(price_pln) AS min_pln,
           MAX(price_pln) AS max_pln,
           AVG(price_pln) AS avg_pln
    FROM base
    GROUP BY product_key
),
lo AS (  -- najtanszy rynek
    SELECT b.product_key, g.country_name AS cheapest_country, g.country_code AS cheapest_cc, b.price_pln,
           ROW_NUMBER() OVER (PARTITION BY b.product_key ORDER BY b.price_pln ASC, g.country_code) rn
    FROM base b JOIN dw.DIM_Geography g ON g.geo_key=b.geo_key
),
hi AS (  -- najdrozszy rynek
    SELECT b.product_key, g.country_name AS dearest_country, g.country_code AS dearest_cc, b.price_pln,
           ROW_NUMBER() OVER (PARTITION BY b.product_key ORDER BY b.price_pln DESC, g.country_code) rn
    FROM base b JOIN dw.DIM_Geography g ON g.geo_key=b.geo_key
)
SELECT
    pr.style_color, pr.product_name, pr.category,
    a.n_markets,
    lo.cheapest_country, lo.cheapest_cc,
    hi.dearest_country,  hi.dearest_cc,
    CAST(a.min_pln AS DECIMAL(12,2)) AS min_price_pln,
    CAST(a.max_pln AS DECIMAL(12,2)) AS max_price_pln,
    CAST(a.avg_pln AS DECIMAL(12,2)) AS avg_price_pln,
    CAST(a.max_pln - a.min_pln AS DECIMAL(12,2)) AS spread_pln,
    CAST(100.0*(a.max_pln - a.min_pln)/NULLIF(a.min_pln,0) AS DECIMAL(8,1)) AS margin_pct,
    CASE WHEN 100.0*(a.max_pln-a.min_pln)/NULLIF(a.min_pln,0) > 20 THEN 'HIGH (>20%)'
         WHEN 100.0*(a.max_pln-a.min_pln)/NULLIF(a.min_pln,0) >= 10 THEN 'MEDIUM (10-20%)'
         ELSE 'LOW (<10%)' END AS arbitrage_status
FROM agg a
JOIN dw.DIM_Product pr ON pr.product_key=a.product_key AND pr.is_current=1
JOIN lo ON lo.product_key=a.product_key AND lo.rn=1
JOIN hi ON hi.product_key=a.product_key AND hi.rn=1
WHERE a.n_markets >= 2;
GO

/* ---------- bi.v_global_price_map : cena PLN per produkt x kraj (mapa) ---------- */
IF OBJECT_ID('bi.v_global_price_map') IS NOT NULL DROP VIEW bi.v_global_price_map;
GO
CREATE VIEW bi.v_global_price_map AS
SELECT pr.style_color, pr.product_name, pr.category,
       g.country_code, g.country_name, g.region,
       c.currency_code, f.local_price, f.price_pln
FROM dw.FACT_Prices f
JOIN dw.DIM_Product   pr ON pr.product_key=f.product_key
JOIN dw.DIM_Geography g  ON g.geo_key=f.geo_key
JOIN dw.DIM_Currency  c  ON c.currency_key=f.currency_key
WHERE f.price_pln IS NOT NULL AND f.price_pln BETWEEN 1 AND 50000;
GO

/* ---------- bi.v_fx_enriched : kursy + atrybuty daty ---------- */
IF OBJECT_ID('bi.v_fx_enriched') IS NOT NULL DROP VIEW bi.v_fx_enriched;
GO
CREATE VIEW bi.v_fx_enriched AS
SELECT f.fx_key, d.full_date AS effective_date, d.[year], d.[quarter], d.[month], d.month_name,
       c.currency_code, c.currency_name, c.nbp_table_type AS currency_tab,
       f.table_type, f.mid_rate, f.bid_rate, f.ask_rate, f.spread
FROM dw.FACT_ExchangeRates f
JOIN dw.DIM_Date     d ON d.date_key=f.date_key
JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key;
GO

/* ---------- bi.v_fx_trend_30d : kurs biezacy vs 30 dni temu (tabela A) ---------- */
IF OBJECT_ID('bi.v_fx_trend_30d') IS NOT NULL DROP VIEW bi.v_fx_trend_30d;
GO
CREATE VIEW bi.v_fx_trend_30d AS
WITH a AS (
    SELECT c.currency_code, c.currency_name, f.effective_date, f.mid_rate
    FROM dw.FACT_ExchangeRates f
    JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
    WHERE f.table_type='A' AND f.mid_rate IS NOT NULL
),
last_day AS (SELECT MAX(effective_date) md FROM a),
cur AS (
    SELECT a.currency_code, a.currency_name, a.mid_rate AS mid_now, a.effective_date AS d_now
    FROM a JOIN last_day ld ON a.effective_date=ld.md
),
prev AS (   -- kurs z najblizszej daty <= (ostatni-30 dni)
    SELECT a.currency_code, a.mid_rate AS mid_prev,
           ROW_NUMBER() OVER (PARTITION BY a.currency_code ORDER BY a.effective_date DESC) rn
    FROM a CROSS JOIN last_day ld
    WHERE a.effective_date <= DATEADD(DAY,-30,ld.md)
)
SELECT cur.currency_code, cur.currency_name, cur.d_now AS as_of_date,
       CAST(cur.mid_now AS DECIMAL(18,6))  AS mid_now,
       CAST(p.mid_prev  AS DECIMAL(18,6))  AS mid_30d_ago,
       CAST(100.0*(cur.mid_now - p.mid_prev)/NULLIF(p.mid_prev,0) AS DECIMAL(8,3)) AS change_30d_pct
FROM cur LEFT JOIN prev p ON p.currency_code=cur.currency_code AND p.rn=1;
GO

/* ---------- bi.v_fx_monthly_volatility : zmiennosc miesieczna (heatmapa) ---------- */
IF OBJECT_ID('bi.v_fx_monthly_volatility') IS NOT NULL DROP VIEW bi.v_fx_monthly_volatility;
GO
CREATE VIEW bi.v_fx_monthly_volatility AS
SELECT c.currency_code, d.[year], d.[month], d.month_name,
       CAST(STDEV(f.mid_rate) AS DECIMAL(18,6)) AS vol_stdev,
       CAST(AVG(f.mid_rate)   AS DECIMAL(18,6)) AS vol_avg,
       CAST(100.0*STDEV(f.mid_rate)/NULLIF(AVG(f.mid_rate),0) AS DECIMAL(8,3)) AS vol_cv_pct
FROM dw.FACT_ExchangeRates f
JOIN dw.DIM_Date     d ON d.date_key=f.date_key
JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
WHERE f.table_type='A' AND f.mid_rate IS NOT NULL
GROUP BY c.currency_code, d.[year], d.[month], d.month_name;
GO

/* ---------- bi.v_kpi_summary : globalne KPI ---------- */
IF OBJECT_ID('bi.v_kpi_summary') IS NOT NULL DROP VIEW bi.v_kpi_summary;
GO
CREATE VIEW bi.v_kpi_summary AS
SELECT
   (SELECT COUNT(*) FROM dw.DIM_Product WHERE is_current=1)            AS products,
   (SELECT COUNT(*) FROM dw.DIM_Geography)                             AS markets,
   (SELECT COUNT(DISTINCT currency_code) FROM dw.DIM_Geography)        AS currencies,
   (SELECT COUNT(*) FROM dw.FACT_Prices)                              AS fact_price_rows,
   (SELECT COUNT(*) FROM bi.v_product_arbitrage)                       AS arbitrage_products,
   (SELECT COUNT(*) FROM bi.v_product_arbitrage WHERE margin_pct>20)   AS opportunities_gt20,
   (SELECT CAST(MAX(margin_pct) AS DECIMAL(8,1)) FROM bi.v_product_arbitrage) AS max_margin_pct,
   (SELECT CAST(MAX(spread_pln) AS DECIMAL(12,2)) FROM bi.v_product_arbitrage) AS max_spread_pln;
GO
PRINT 'NFX_DW: widoki warstwy BI (schemat bi) utworzone.';
GO
