/* =====================================================================
   NFX – Nike Foreign Exchange  |  02_dim_tables.sql
   Tabele wymiarow (schemat gwiazdy). Dostosowane do RZECZYWISTEGO
   schematu pliku Global_Nike.csv (zweryfikowanego profilowaniem).

   ZMIANA WZGLEDEM KM1: naturalnym kluczem produktu jest `style_color`
   (model + kolorystyka, np. NIKGD001K01-TYD), a nie UUID `sku` (ten jest
   per rozmiar). Atrybuty produktu: model_number, product_name, color_name,
   gender_segment, category. Podkategoria jest zlokalizowana per rynek,
   wiec trafia do DIM_Category (poziom 2), nie do DIM_Product.
   ===================================================================== */
USE NFX_DW;
GO

/* ---------- DIM_Date ---------- */
IF OBJECT_ID('dw.DIM_Date') IS NOT NULL DROP TABLE dw.DIM_Date;
GO
CREATE TABLE dw.DIM_Date (
    date_key            INT          NOT NULL PRIMARY KEY,   -- YYYYMMDD
    full_date           DATE         NOT NULL,
    [year]              SMALLINT     NOT NULL,
    [quarter]           TINYINT      NOT NULL,
    [month]             TINYINT      NOT NULL,
    month_name          VARCHAR(20)  NOT NULL,
    week_of_year        TINYINT      NOT NULL,
    day_of_week         TINYINT      NOT NULL,   -- 1=Poniedzialek
    is_weekend          BIT          NOT NULL,
    is_nbp_working_day  BIT          NOT NULL,
    CONSTRAINT UQ_Date_full UNIQUE (full_date)
);
GO

/* ---------- DIM_Currency (SCD1 na current_mid_rate) ---------- */
IF OBJECT_ID('dw.DIM_Currency') IS NOT NULL DROP TABLE dw.DIM_Currency;
GO
CREATE TABLE dw.DIM_Currency (
    currency_key        INT IDENTITY(1,1) PRIMARY KEY,
    currency_code       CHAR(3)       NOT NULL,
    currency_name       NVARCHAR(100) NOT NULL,   -- nazwa (EN/uniwersalna)
    currency_name_pl    NVARCHAR(120) NULL,       -- nazwa PL z NBP (diakrytyki)
    nbp_table_type      CHAR(1)       NULL,        -- A / B / C / NULL(=PLN bazowa)
    is_base_currency    BIT           NOT NULL DEFAULT 0,   -- PLN = 1
    current_mid_rate    DECIMAL(18,6) NULL,        -- SCD1: ostatni kurs mid wzgledem PLN
    CONSTRAINT UQ_Currency UNIQUE (currency_code)
);
GO

/* ---------- DIM_Geography ---------- */
IF OBJECT_ID('dw.DIM_Geography') IS NOT NULL DROP TABLE dw.DIM_Geography;
GO
CREATE TABLE dw.DIM_Geography (
    geo_key       INT IDENTITY(1,1) PRIMARY KEY,
    country_code  CHAR(2)      NOT NULL,
    country_name  VARCHAR(100) NOT NULL,
    region        VARCHAR(50)  NOT NULL,   -- segment operacyjny Nike (NA / EMEA / Greater China / APLA)
    sub_region    VARCHAR(50)  NULL,
    currency_code CHAR(3)      NOT NULL,   -- waluta wiodaca rynku (z danych)
    CONSTRAINT UQ_Geo UNIQUE (country_code)
);
GO

/* ---------- DIM_Category (hierarchia samoodnoszaca: Category -> Subcategory) ---------- */
IF OBJECT_ID('dw.DIM_Category') IS NOT NULL DROP TABLE dw.DIM_Category;
GO
CREATE TABLE dw.DIM_Category (
    category_key        INT IDENTITY(1,1) PRIMARY KEY,
    category            VARCHAR(50)   NOT NULL,   -- FOOTWEAR / APPAREL / EQUIPMENT ...
    subcategory         NVARCHAR(200) NOT NULL,   -- etykieta zlokalizowana rynku (poziom 2), Unicode (CJK)
    category_level      TINYINT      NOT NULL,   -- 1 = glowna, 2 = podkategoria
    parent_category_key INT          NULL
        REFERENCES dw.DIM_Category(category_key),
    CONSTRAINT UQ_Category UNIQUE (category, subcategory)
);
GO

/* ---------- DIM_Product (SCD Typ 2) ---------- */
IF OBJECT_ID('dw.DIM_Product') IS NOT NULL DROP TABLE dw.DIM_Product;
GO
CREATE TABLE dw.DIM_Product (
    product_key    INT IDENTITY(1,1) PRIMARY KEY,
    style_color    VARCHAR(60)   NOT NULL,   -- KLUCZ NATURALNY (model + kolor)
    model_number   VARCHAR(50)   NOT NULL,   -- kod stylu (bez koloru/rozmiaru)
    product_name   NVARCHAR(300) NOT NULL,   -- moze zawierac znaki zlokalizowane
    color_name     NVARCHAR(120) NULL,
    gender_segment VARCHAR(40)   NULL,
    category       VARCHAR(50)  NOT NULL,   -- poziom 1 (stabilny dla produktu)
    valid_from     DATE         NOT NULL,
    valid_to       DATE         NULL,        -- NULL = aktualny
    is_current     BIT          NOT NULL,
    etl_load_date  DATETIME     NOT NULL
);
GO
CREATE INDEX IX_Product_StyleColor_Current ON dw.DIM_Product(style_color, is_current);
GO
PRINT 'NFX_DW: tabele wymiarow utworzone.';
GO
