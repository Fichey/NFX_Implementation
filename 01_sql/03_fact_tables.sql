/* =====================================================================
   NFX – Nike Foreign Exchange  |  03_fact_tables.sql
   Tabele faktow gwiazdy.
   ===================================================================== */
USE NFX_DW;
GO

/* ---------- FACT_Prices (1 wiersz = 1 produkt w 1 kraju w 1 dacie snapshotu) ---------- */
IF OBJECT_ID('dw.FACT_Prices') IS NOT NULL DROP TABLE dw.FACT_Prices;
GO
CREATE TABLE dw.FACT_Prices (
    price_key          BIGINT IDENTITY(1,1) PRIMARY KEY,
    product_key        INT NOT NULL REFERENCES dw.DIM_Product(product_key),
    geo_key            INT NOT NULL REFERENCES dw.DIM_Geography(geo_key),
    currency_key       INT NOT NULL REFERENCES dw.DIM_Currency(currency_key),
    date_key           INT NOT NULL REFERENCES dw.DIM_Date(date_key),
    category_key       INT NOT NULL REFERENCES dw.DIM_Category(category_key),
    local_price        DECIMAL(12,2) NOT NULL,   -- cena katalogowa MSRP w walucie lokalnej
    sale_price_local   DECIMAL(12,2) NULL,        -- cena promocyjna (jesli jest)
    discount_pct       DECIMAL(6,2)  NULL,
    price_pln          DECIMAL(14,4) NULL,        -- snapshot ETL: local_price * mid(snapshot)
    price_eur          DECIMAL(14,4) NULL,        -- kurs krzyzowy przez PLN
    price_usd          DECIMAL(14,4) NULL,
    in_stock           BIT           NULL,
    is_catalogue_price BIT NOT NULL DEFAULT 1,
    etl_load_date      DATETIME NOT NULL,
    CONSTRAINT UQ_FactPrices UNIQUE (product_key, geo_key, date_key)   -- ziarno
);
GO
CREATE INDEX IX_FactPrices_Date    ON dw.FACT_Prices(date_key);
CREATE INDEX IX_FactPrices_Geo     ON dw.FACT_Prices(geo_key);
CREATE INDEX IX_FactPrices_Curr    ON dw.FACT_Prices(currency_key);
GO

/* ---------- FACT_ExchangeRates (1 wiersz = kurs waluty na 1 dzien roboczy NBP) ---------- */
IF OBJECT_ID('dw.FACT_ExchangeRates') IS NOT NULL DROP TABLE dw.FACT_ExchangeRates;
GO
CREATE TABLE dw.FACT_ExchangeRates (
    fx_key         BIGINT IDENTITY(1,1) PRIMARY KEY,
    date_key       INT NOT NULL REFERENCES dw.DIM_Date(date_key),
    currency_key   INT NOT NULL REFERENCES dw.DIM_Currency(currency_key),
    table_type     CHAR(1) NOT NULL,
    table_no       VARCHAR(20) NOT NULL,
    mid_rate       DECIMAL(18,6) NULL,
    bid_rate       DECIMAL(18,6) NULL,
    ask_rate       DECIMAL(18,6) NULL,
    spread         DECIMAL(18,6) NULL,           -- ask - bid (tabela C)
    trading_date   DATE NULL,
    effective_date DATE NOT NULL,
    fx_source      VARCHAR(20) NOT NULL DEFAULT 'NBP',
    load_timestamp DATETIME NOT NULL,
    CONSTRAINT UQ_FX UNIQUE (effective_date, currency_key, table_type)  -- klucz deduplikacji
);
GO
CREATE INDEX IX_FX_Date ON dw.FACT_ExchangeRates(date_key);
CREATE INDEX IX_FX_Curr ON dw.FACT_ExchangeRates(currency_key);
GO
PRINT 'NFX_DW: tabele faktow utworzone.';
GO
