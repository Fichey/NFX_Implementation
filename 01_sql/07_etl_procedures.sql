/* =====================================================================
   NFX – Nike Foreign Exchange  |  07_etl_procedures.sql
   Procedury ladowania wymiarow i faktow (logika "Execute SQL Task" z SSIS).
   Wywolywane przez orkiestrator (02_etl/run_etl.py) PO zaladowaniu staging.

   Procedury:
     dw.usp_LoadDimCurrency        - slownik walut (NBP A/B/C + waluty katalogu + PLN), SCD1 osobno
     dw.usp_LoadDimCategory        - hierarchia Category -> Subcategory (samoodnoszaca)
     dw.usp_LoadDimProduct_SCD2    - DIM_Product z obsluga SCD Typ 2
     dw.usp_LoadFactExchangeRates  - FACT_ExchangeRates + deduplikacja + SCD1 kursu
     dw.usp_LoadFactPrices         - FACT_Prices + przeliczenie PLN/EUR/USD + odrzuty
     dw.usp_LoadWarehouse          - orkiestracja wszystkich powyzszych
   ===================================================================== */
USE NFX_DW;
GO
-------------------------------------------------------------------------
IF OBJECT_ID('dw.usp_LoadDimCurrency') IS NOT NULL DROP PROCEDURE dw.usp_LoadDimCurrency;
GO
CREATE PROCEDURE dw.usp_LoadDimCurrency AS
BEGIN
    SET NOCOUNT ON;
    -- 1. waluty z NBP (priorytet tabeli A < B < C)
    ;WITH src AS (
        SELECT code,
               MAX(currency_name_pl) AS name_pl,
               MIN(CASE table_type WHEN 'A' THEN 1 WHEN 'B' THEN 2 ELSE 3 END) AS rnk
        FROM staging.stg_fx_rates
        WHERE code IS NOT NULL
        GROUP BY code
    )
    MERGE dw.DIM_Currency AS tgt
    USING (SELECT code, name_pl,
                  CASE rnk WHEN 1 THEN 'A' WHEN 2 THEN 'B' ELSE 'C' END AS tt
           FROM src) AS s
    ON tgt.currency_code = s.code
    WHEN MATCHED THEN
        UPDATE SET currency_name_pl = s.name_pl, nbp_table_type = s.tt
    WHEN NOT MATCHED THEN
        INSERT (currency_code, currency_name, currency_name_pl, nbp_table_type, is_base_currency)
        VALUES (s.code, s.name_pl, s.name_pl, s.tt, 0);

    -- 2. waluty z katalogu nieobecne w NBP (np. BGN) -> bez tabeli, kurs NULL
    INSERT INTO dw.DIM_Currency (currency_code, currency_name, currency_name_pl, nbp_table_type, is_base_currency)
    SELECT DISTINCT s.currency, s.currency, NULL, NULL, 0
    FROM staging.stg_nike_prices s
    WHERE s.currency IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dw.DIM_Currency c WHERE c.currency_code = s.currency);

    -- 3. PLN jako waluta bazowa (kurs = 1)
    IF EXISTS (SELECT 1 FROM dw.DIM_Currency WHERE currency_code='PLN')
        UPDATE dw.DIM_Currency SET is_base_currency=1, current_mid_rate=1.0,
               currency_name='Polish zloty', currency_name_pl=N'złoty polski'
        WHERE currency_code='PLN';
    ELSE
        INSERT INTO dw.DIM_Currency (currency_code,currency_name,currency_name_pl,nbp_table_type,is_base_currency,current_mid_rate)
        VALUES ('PLN','Polish zloty',N'złoty polski',NULL,1,1.0);

    -- 4. czytelne nazwy EN dla glownych walut katalogu (raporty)
    UPDATE dw.DIM_Currency SET currency_name = m.en
    FROM dw.DIM_Currency c
    JOIN (VALUES
        ('USD','US Dollar'),('EUR','Euro'),('GBP','British Pound'),('JPY','Japanese Yen'),
        ('CHF','Swiss Franc'),('CNY','Chinese Yuan'),('CAD','Canadian Dollar'),('AUD','Australian Dollar'),
        ('NZD','New Zealand Dollar'),('SEK','Swedish Krona'),('NOK','Norwegian Krone'),('DKK','Danish Krone'),
        ('RON','Romanian Leu'),('TRY','Turkish Lira'),('ILS','Israeli Shekel'),('ZAR','South African Rand'),
        ('MXN','Mexican Peso'),('SGD','Singapore Dollar'),('THB','Thai Baht'),('MYR','Malaysian Ringgit'),
        ('TWD','Taiwan Dollar'),('IDR','Indonesian Rupiah'),('VND','Vietnamese Dong'),('KRW','South Korean Won'),
        ('PHP','Philippine Peso'),('INR','Indian Rupee'),('EGP','Egyptian Pound'),('BGN','Bulgarian Lev')
    ) AS m(code,en) ON m.code = c.currency_code;
END
GO
-------------------------------------------------------------------------
IF OBJECT_ID('dw.usp_LoadDimCategory') IS NOT NULL DROP PROCEDURE dw.usp_LoadDimCategory;
GO
CREATE PROCEDURE dw.usp_LoadDimCategory AS
BEGIN
    SET NOCOUNT ON;
    -- poziom 1: kategorie glowne (wezel rollup, subcategory = category)
    INSERT INTO dw.DIM_Category (category, subcategory, category_level, parent_category_key)
    SELECT DISTINCT s.category, s.category, 1, NULL
    FROM staging.stg_nike_prices s
    WHERE s.category IS NOT NULL
      AND NOT EXISTS (SELECT 1 FROM dw.DIM_Category c
                      WHERE c.category=s.category AND c.category_level=1);
    -- poziom 2: podkategorie (zlokalizowane) z rodzicem
    INSERT INTO dw.DIM_Category (category, subcategory, category_level, parent_category_key)
    SELECT DISTINCT s.category, s.subcategory, 2, p.category_key
    FROM staging.stg_nike_prices s
    JOIN dw.DIM_Category p ON p.category=s.category AND p.category_level=1
    WHERE s.subcategory IS NOT NULL
      AND s.subcategory <> s.category
      AND NOT EXISTS (SELECT 1 FROM dw.DIM_Category c
                      WHERE c.category=s.category AND c.subcategory=s.subcategory AND c.category_level=2);
END
GO
-------------------------------------------------------------------------
IF OBJECT_ID('dw.usp_LoadDimProduct_SCD2') IS NOT NULL DROP PROCEDURE dw.usp_LoadDimProduct_SCD2;
GO
CREATE PROCEDURE dw.usp_LoadDimProduct_SCD2 @load_date DATE = NULL AS
BEGIN
    SET NOCOUNT ON;
    IF @load_date IS NULL SET @load_date = CAST(GETDATE() AS DATE);

    -- kanoniczny rekord produktu: 1 wiersz na style_color, preferuj rynek EN (US>GB>IE>AU)
    ;WITH ranked AS (
        SELECT style_color, model_number, product_name, color_name, gender_segment, category,
               ROW_NUMBER() OVER (PARTITION BY style_color
                   ORDER BY CASE country_code WHEN 'US' THEN 1 WHEN 'GB' THEN 2
                                              WHEN 'IE' THEN 3 WHEN 'AU' THEN 4 ELSE 9 END,
                            country_code) AS rn
        FROM staging.stg_nike_prices
        WHERE style_color IS NOT NULL
    ),
    src AS (SELECT * FROM ranked WHERE rn = 1)
    -- 1. SCD2: zamknij biezace wersje, gdy zmienil sie sledzony atrybut
    UPDATE p SET p.valid_to = DATEADD(DAY,-1,@load_date), p.is_current = 0
    FROM dw.DIM_Product p
    JOIN src s ON s.style_color = p.style_color
    WHERE p.is_current = 1
      AND ( ISNULL(p.product_name,'')   <> ISNULL(s.product_name,'')
         OR ISNULL(p.color_name,'')     <> ISNULL(s.color_name,'')
         OR ISNULL(p.gender_segment,'') <> ISNULL(s.gender_segment,'')
         OR ISNULL(p.category,'')       <> ISNULL(s.category,'')
         OR ISNULL(p.model_number,'')   <> ISNULL(s.model_number,'') );

    -- 2. wstaw nowe wersje (nowe produkty oraz przed chwila zamkniete)
    ;WITH ranked AS (
        SELECT style_color, model_number, product_name, color_name, gender_segment, category,
               ROW_NUMBER() OVER (PARTITION BY style_color
                   ORDER BY CASE country_code WHEN 'US' THEN 1 WHEN 'GB' THEN 2
                                              WHEN 'IE' THEN 3 WHEN 'AU' THEN 4 ELSE 9 END,
                            country_code) AS rn
        FROM staging.stg_nike_prices
        WHERE style_color IS NOT NULL
    ),
    src AS (SELECT * FROM ranked WHERE rn = 1)
    INSERT INTO dw.DIM_Product (style_color, model_number, product_name, color_name, gender_segment,
                                category, valid_from, valid_to, is_current, etl_load_date)
    SELECT s.style_color, s.model_number, s.product_name, s.color_name, s.gender_segment,
           s.category, @load_date, NULL, 1, GETDATE()
    FROM src s
    WHERE NOT EXISTS (SELECT 1 FROM dw.DIM_Product p
                      WHERE p.style_color = s.style_color AND p.is_current = 1);
END
GO
-------------------------------------------------------------------------
IF OBJECT_ID('dw.usp_LoadFactExchangeRates') IS NOT NULL DROP PROCEDURE dw.usp_LoadFactExchangeRates;
GO
CREATE PROCEDURE dw.usp_LoadFactExchangeRates AS
BEGIN
    SET NOCOUNT ON;
    INSERT INTO dw.FACT_ExchangeRates (date_key, currency_key, table_type, table_no,
           mid_rate, bid_rate, ask_rate, spread, trading_date, effective_date, fx_source, load_timestamp)
    SELECT d.date_key, c.currency_key, s.table_type, s.table_no,
           TRY_CONVERT(DECIMAL(18,6), s.mid),
           TRY_CONVERT(DECIMAL(18,6), s.bid),
           TRY_CONVERT(DECIMAL(18,6), s.ask),
           TRY_CONVERT(DECIMAL(18,6), s.ask) - TRY_CONVERT(DECIMAL(18,6), s.bid),
           TRY_CONVERT(DATE, s.trading_date),
           TRY_CONVERT(DATE, s.effective_date),
           'NBP', GETDATE()
    FROM staging.stg_fx_rates s
    JOIN dw.DIM_Currency c ON c.currency_code = s.code
    JOIN dw.DIM_Date d ON d.full_date = TRY_CONVERT(DATE, s.effective_date)
    WHERE s.code IS NOT NULL
      AND NOT EXISTS (                              -- deduplikacja
          SELECT 1 FROM dw.FACT_ExchangeRates f
          WHERE f.effective_date = TRY_CONVERT(DATE, s.effective_date)
            AND f.currency_key   = c.currency_key
            AND f.table_type     = s.table_type);

    -- SCD1: nadpisz aktualny kurs mid w DIM_Currency
    ;WITH latest AS (
        SELECT currency_key, mid_rate,
               ROW_NUMBER() OVER (PARTITION BY currency_key ORDER BY effective_date DESC) rn
        FROM dw.FACT_ExchangeRates
        WHERE table_type IN ('A','B') AND mid_rate IS NOT NULL
    )
    UPDATE c SET c.current_mid_rate = l.mid_rate
    FROM dw.DIM_Currency c
    JOIN latest l ON l.currency_key = c.currency_key AND l.rn = 1;
END
GO
-------------------------------------------------------------------------
IF OBJECT_ID('dw.usp_LoadFactPrices') IS NOT NULL DROP PROCEDURE dw.usp_LoadFactPrices;
GO
CREATE PROCEDURE dw.usp_LoadFactPrices @load_batch_id INT = NULL AS
BEGIN
    SET NOCOUNT ON;

    -- 0. error_log dla katalogu jest przeliczany przy kazdym pelnym ladowaniu staging
    DELETE FROM staging.error_log WHERE source_table = 'stg_nike_prices';

    -- 1. odrzuc niepoprawne wiersze do error_log
    INSERT INTO staging.error_log (source_table, raw_row, reject_reason, load_batch_id)
    SELECT 'stg_nike_prices',
           CONCAT('style_color=', style_color, '|country=', country_code, '|price=', price_local),
           CASE WHEN style_color IS NULL THEN 'style_color NULL'
                WHEN price_local IS NULL THEN 'price NULL'
                WHEN TRY_CONVERT(DECIMAL(12,2), price_local) IS NULL THEN 'price not numeric'
                WHEN TRY_CONVERT(DECIMAL(12,2), price_local) <= 0 THEN 'price <= 0'
                ELSE 'unknown' END,
           @load_batch_id
    FROM staging.stg_nike_prices
    WHERE style_color IS NULL OR price_local IS NULL
       OR TRY_CONVERT(DECIMAL(12,2), price_local) IS NULL
       OR TRY_CONVERT(DECIMAL(12,2), price_local) <= 0;

    -- 2. data snapshotu i kursy obowiazujace na ten dzien (ostatni mid A/B <= snapshot)
    DECLARE @snapshot DATE = (SELECT TRY_CONVERT(DATE, MAX(snapshot_date)) FROM staging.stg_nike_prices);

    ;WITH rate AS (
        SELECT c.currency_code, f.mid_rate,
               ROW_NUMBER() OVER (PARTITION BY c.currency_code ORDER BY f.effective_date DESC) rn
        FROM dw.FACT_ExchangeRates f
        JOIN dw.DIM_Currency c ON c.currency_key = f.currency_key
        WHERE f.table_type IN ('A','B') AND f.mid_rate IS NOT NULL
          AND f.effective_date <= @snapshot
    ),
    eff_rate AS (
        SELECT currency_code, mid_rate FROM rate WHERE rn = 1
        UNION ALL SELECT 'PLN', CAST(1.0 AS DECIMAL(18,6))
    ),
    eur AS (SELECT mid_rate r FROM eff_rate WHERE currency_code='EUR'),
    usd AS (SELECT mid_rate r FROM eff_rate WHERE currency_code='USD')
    INSERT INTO dw.FACT_Prices (product_key, geo_key, currency_key, date_key, category_key,
           local_price, sale_price_local, discount_pct, price_pln, price_eur, price_usd,
           in_stock, is_catalogue_price, etl_load_date)
    SELECT
        p.product_key, g.geo_key, c.currency_key, d.date_key, cat.category_key,
        TRY_CONVERT(DECIMAL(12,2), s.price_local),
        TRY_CONVERT(DECIMAL(12,2), s.sale_price_local),
        TRY_CONVERT(DECIMAL(6,2),  s.discount_pct),
        CAST(TRY_CONVERT(DECIMAL(12,2), s.price_local) * er.mid_rate AS DECIMAL(14,4))                      AS price_pln,
        CASE WHEN (SELECT r FROM eur) > 0
             THEN CAST(TRY_CONVERT(DECIMAL(12,2), s.price_local) * er.mid_rate / (SELECT r FROM eur) AS DECIMAL(14,4)) END AS price_eur,
        CASE WHEN (SELECT r FROM usd) > 0
             THEN CAST(TRY_CONVERT(DECIMAL(12,2), s.price_local) * er.mid_rate / (SELECT r FROM usd) AS DECIMAL(14,4)) END AS price_usd,
        CASE WHEN s.in_stock IN ('True','true','1') THEN 1
             WHEN s.in_stock IN ('False','false','0') THEN 0 END,
        1, GETDATE()
    FROM staging.stg_nike_prices s
    JOIN dw.DIM_Product   p   ON p.style_color = s.style_color AND p.is_current = 1
    JOIN dw.DIM_Geography g   ON g.country_code = s.country_code
    JOIN dw.DIM_Currency  c   ON c.currency_code = s.currency
    JOIN dw.DIM_Date      d   ON d.full_date = TRY_CONVERT(DATE, s.snapshot_date)
    JOIN dw.DIM_Category  cat ON cat.category = s.category AND cat.subcategory = s.subcategory AND cat.category_level = 2
    LEFT JOIN eff_rate    er  ON er.currency_code = s.currency
    WHERE s.style_color IS NOT NULL
      AND TRY_CONVERT(DECIMAL(12,2), s.price_local) > 0
      AND NOT EXISTS (SELECT 1 FROM dw.FACT_Prices fp
                      WHERE fp.product_key = p.product_key AND fp.geo_key = g.geo_key AND fp.date_key = d.date_key);
END
GO
-------------------------------------------------------------------------
IF OBJECT_ID('dw.usp_LoadWarehouse') IS NOT NULL DROP PROCEDURE dw.usp_LoadWarehouse;
GO
CREATE PROCEDURE dw.usp_LoadWarehouse @load_batch_id INT = NULL, @load_date DATE = NULL AS
BEGIN
    SET NOCOUNT ON;
    EXEC dw.usp_LoadDimCurrency;
    EXEC dw.usp_LoadDimCategory;
    EXEC dw.usp_LoadDimProduct_SCD2 @load_date = @load_date;
    EXEC dw.usp_LoadFactExchangeRates;
    EXEC dw.usp_LoadFactPrices @load_batch_id = @load_batch_id;
    EXEC dw.usp_RefreshNbpWorkingDays;
END
GO
PRINT 'NFX_DW: procedury ETL utworzone.';
GO
