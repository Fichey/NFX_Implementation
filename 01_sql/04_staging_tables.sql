/* =====================================================================
   NFX – Nike Foreign Exchange  |  04_staging_tables.sql
   Tabele warstwy staging: lustro danych zrodlowych (wszystko jako tekst),
   log bledow (odrzucone wiersze) oraz log audytu przebiegow ETL.
   ===================================================================== */
USE NFX_DW;
GO

/* ---------- staging.stg_nike_prices ----------
   Ziarno produkt x kraj x data (po deduplikacji rozmiarow w ekstrakcji).
   Kolumny 1:1 z plikiem nike_product_country.csv. Wszystko NVARCHAR. */
IF OBJECT_ID('staging.stg_nike_prices') IS NOT NULL DROP TABLE staging.stg_nike_prices;
GO
CREATE TABLE staging.stg_nike_prices (
    style_color        NVARCHAR(100),
    country_code       NVARCHAR(10),
    snapshot_date      NVARCHAR(30),
    model_number       NVARCHAR(100),
    product_name       NVARCHAR(400),
    color_name         NVARCHAR(200),
    gender_segment     NVARCHAR(60),
    category           NVARCHAR(60),
    subcategory        NVARCHAR(300),
    currency           NVARCHAR(10),
    price_local        NVARCHAR(40),
    sale_price_local   NVARCHAR(40),
    discount_pct       NVARCHAR(40),
    in_stock           NVARCHAR(20),
    availability_level NVARCHAR(20),
    load_batch_id      INT NULL
);
GO

/* ---------- staging.stg_fx_rates ----------
   Splaszczony JSON NBP (tabele A/B/C). Wszystko NVARCHAR. */
IF OBJECT_ID('staging.stg_fx_rates') IS NOT NULL DROP TABLE staging.stg_fx_rates;
GO
CREATE TABLE staging.stg_fx_rates (
    table_type        NVARCHAR(5),
    table_no          NVARCHAR(30),
    effective_date    NVARCHAR(30),
    trading_date      NVARCHAR(30),
    code              NVARCHAR(10),
    currency_name_pl  NVARCHAR(150),
    mid               NVARCHAR(40),
    bid               NVARCHAR(40),
    ask               NVARCHAR(40),
    load_batch_id     INT NULL
);
GO

/* ---------- staging.error_log (wiersze odrzucone) ---------- */
IF OBJECT_ID('staging.error_log') IS NOT NULL DROP TABLE staging.error_log;
GO
CREATE TABLE staging.error_log (
    error_id      BIGINT IDENTITY(1,1) PRIMARY KEY,
    source_table  VARCHAR(50),
    raw_row       NVARCHAR(MAX),
    reject_reason VARCHAR(200),
    load_batch_id INT NULL,
    logged_at     DATETIME DEFAULT GETDATE()
);
GO

/* ---------- staging.etl_run_log (audyt przebiegow) ---------- */
IF OBJECT_ID('staging.etl_run_log') IS NOT NULL DROP TABLE staging.etl_run_log;
GO
CREATE TABLE staging.etl_run_log (
    run_id        INT IDENTITY(1,1) PRIMARY KEY,
    package_name  VARCHAR(80)  NOT NULL,
    load_type     VARCHAR(20)  NOT NULL,   -- INITIAL / INCREMENTAL
    start_time    DATETIME     NOT NULL,
    end_time      DATETIME     NULL,
    rows_in       INT          NULL,
    rows_out      INT          NULL,
    rows_rejected INT          NULL,
    status        VARCHAR(20)  NULL,       -- RUNNING / SUCCESS / FAILED
    message       NVARCHAR(500) NULL
);
GO
PRINT 'NFX_DW: tabele staging utworzone.';
GO
