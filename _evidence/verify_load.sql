USE NFX_DW;
SET NOCOUNT ON;
PRINT '--- Liczby wierszy w tabelach ---';
SELECT 'DIM_Product' t, COUNT(*) n FROM dw.DIM_Product
UNION ALL SELECT 'DIM_Currency', COUNT(*) FROM dw.DIM_Currency
UNION ALL SELECT 'DIM_Category', COUNT(*) FROM dw.DIM_Category
UNION ALL SELECT 'DIM_Geography', COUNT(*) FROM dw.DIM_Geography
UNION ALL SELECT 'FACT_Prices', COUNT(*) FROM dw.FACT_Prices
UNION ALL SELECT 'FACT_ExchangeRates', COUNT(*) FROM dw.FACT_ExchangeRates
UNION ALL SELECT 'FACT_Prices price_pln NULL', COUNT(*) FROM dw.FACT_Prices WHERE price_pln IS NULL
UNION ALL SELECT 'error_log', COUNT(*) FROM staging.error_log;

PRINT '';
PRINT '--- Kontrola przeliczenia: NIKGD001K01-TYD (US, USD 110) ---';
SELECT TOP 5 g.country_code, c.currency_code, f.local_price, f.price_pln, f.price_usd, f.price_eur
FROM dw.FACT_Prices f
JOIN dw.DIM_Product p ON p.product_key=f.product_key
JOIN dw.DIM_Geography g ON g.geo_key=f.geo_key
JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
WHERE p.style_color='NIKGD001K01-TYD';

PRINT '';
PRINT '--- TOP 10 arbitraz: produkt w >=5 krajach, najwiekszy spread PLN ---';
WITH agg AS (
  SELECT f.product_key,
         COUNT(DISTINCT f.geo_key) AS n_markets,
         MIN(f.price_pln) AS min_pln, MAX(f.price_pln) AS max_pln
  FROM dw.FACT_Prices f
  WHERE f.price_pln IS NOT NULL
  GROUP BY f.product_key
  HAVING COUNT(DISTINCT f.geo_key) >= 5
)
SELECT TOP 10 p.style_color, LEFT(p.product_name,30) AS product_name, a.n_markets,
       CAST(a.min_pln AS DECIMAL(10,2)) min_pln, CAST(a.max_pln AS DECIMAL(10,2)) max_pln,
       CAST(a.max_pln-a.min_pln AS DECIMAL(10,2)) AS spread_pln,
       CAST(100.0*(a.max_pln-a.min_pln)/a.min_pln AS DECIMAL(8,1)) AS margin_pct
FROM agg a JOIN dw.DIM_Product p ON p.product_key=a.product_key
ORDER BY (a.max_pln-a.min_pln) DESC;
