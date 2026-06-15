USE NFX_DW;
SET NOCOUNT ON;
PRINT '=== KPI SUMMARY ===';
SELECT * FROM bi.v_kpi_summary;
PRINT '';
PRINT '=== TOP 15 ARBITRAGE (outliery wykluczone, >=5 rynkow) ===';
SELECT TOP 15 style_color, LEFT(product_name,28) product_name, category, n_markets,
       cheapest_cc, dearest_cc, min_price_pln, max_price_pln, spread_pln, margin_pct, arbitrage_status
FROM bi.v_product_arbitrage
WHERE n_markets >= 5
ORDER BY margin_pct DESC;
PRINT '';
PRINT '=== Rozklad statusow arbitrazu ===';
SELECT arbitrage_status, COUNT(*) n FROM bi.v_product_arbitrage GROUP BY arbitrage_status ORDER BY 1;
PRINT '';
PRINT '=== FX trend 30D (tabela A, wybrane) ===';
SELECT currency_code, as_of_date, mid_now, mid_30d_ago, change_30d_pct
FROM bi.v_fx_trend_30d
WHERE currency_code IN ('USD','EUR','GBP','JPY','TRY','ZAR','CHF','KRW')
ORDER BY change_30d_pct DESC;
