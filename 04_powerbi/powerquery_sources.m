// =====================================================================
// NFX – Nike Foreign Exchange | Power Query (M) – zrodla danych
// Tryb: Import. Serwer: localhost, baza: NFX_DW.
// Kazda sekcja = osobne zapytanie (Query) w Power BI Desktop.
// Wymiary/fakty ladujemy z tabel dw.*, a model biznesowy z widokow bi.*.
// =====================================================================

// ---- DIM_Date ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.DIM_Date"])
in
    Source

// ---- DIM_Currency ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.DIM_Currency"])
in
    Source

// ---- DIM_Geography ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.DIM_Geography"])
in
    Source

// ---- DIM_Category ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.DIM_Category"])
in
    Source

// ---- DIM_Product (tylko aktualne wersje SCD2 do raportow operacyjnych;
//      do analiz historycznych usun WHERE is_current=1) ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.DIM_Product WHERE is_current = 1"])
in
    Source

// ---- FACT_Prices ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.FACT_Prices"])
in
    Source

// ---- FACT_ExchangeRates ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM dw.FACT_ExchangeRates"])
in
    Source

// ---- (opcjonalnie) gotowy ranking arbitrazu z warstwy BI ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM bi.v_product_arbitrage"])
in
    Source

// ---- (opcjonalnie) trend kursow 30D ----
let
    Source = Sql.Database("localhost", "NFX_DW", [Query="SELECT * FROM bi.v_fx_trend_30d"])
in
    Source
