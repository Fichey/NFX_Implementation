USE NFX_DW;
SET NOCOUNT ON;
PRINT '--- Rozklad wysokich cen PLN ---';
SELECT
  CASE WHEN price_pln >= 100000 THEN '>=100k'
       WHEN price_pln >= 20000 THEN '20k-100k'
       WHEN price_pln >= 10000 THEN '10k-20k'
       WHEN price_pln >= 5000  THEN '5k-10k'
       WHEN price_pln >= 2000  THEN '2k-5k'
       ELSE '<2k' END AS bucket,
  COUNT(*) n
FROM dw.FACT_Prices WHERE price_pln IS NOT NULL
GROUP BY CASE WHEN price_pln >= 100000 THEN '>=100k'
       WHEN price_pln >= 20000 THEN '20k-100k'
       WHEN price_pln >= 10000 THEN '10k-20k'
       WHEN price_pln >= 5000  THEN '5k-10k'
       WHEN price_pln >= 2000  THEN '2k-5k'
       ELSE '<2k' END
ORDER BY 1;

PRINT '';
PRINT '--- Kto generuje price_pln = 216970 ? ---';
SELECT TOP 10 g.country_code, c.currency_code, f.local_price, f.price_pln, COUNT(*) OVER() total_rows
FROM dw.FACT_Prices f
JOIN dw.DIM_Geography g ON g.geo_key=f.geo_key
JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
WHERE f.price_pln BETWEEN 216900 AND 217000;

PRINT '';
PRINT '--- Ile wierszy ma price_pln >= 20000 wg kraju ---';
SELECT g.country_code, c.currency_code, COUNT(*) n,
       MIN(f.local_price) min_loc, MAX(f.local_price) max_loc
FROM dw.FACT_Prices f
JOIN dw.DIM_Geography g ON g.geo_key=f.geo_key
JOIN dw.DIM_Currency c ON c.currency_key=f.currency_key
WHERE f.price_pln >= 20000
GROUP BY g.country_code, c.currency_code
ORDER BY n DESC;
