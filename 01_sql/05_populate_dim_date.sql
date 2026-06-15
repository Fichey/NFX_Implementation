/* =====================================================================
   NFX – Nike Foreign Exchange  |  05_populate_dim_date.sql
   Wypelnienie DIM_Date: 2002-01-01 .. 2027-12-31 (pokrywa archiwum NBP).
   is_nbp_working_day: wstepnie dzien powszedni minus stale swieta PL;
   ruchome swieta (Wielkanoc itd.) doprecyzowuje ETL na podstawie
   rzeczywistych dat publikacji tabel NBP (procedura dw.usp_RefreshNbpWorkingDays).
   ===================================================================== */
USE NFX_DW;
GO
DELETE FROM dw.DIM_Date;   -- DELETE (nie TRUNCATE) bo tabela jest celem FK z faktow
GO
;WITH d AS (
    SELECT CAST('2002-01-01' AS DATE) AS dt
    UNION ALL SELECT DATEADD(DAY,1,dt) FROM d WHERE dt < '2027-12-31'
)
INSERT INTO dw.DIM_Date (date_key, full_date, [year],[quarter],[month],month_name,
                         week_of_year, day_of_week, is_weekend, is_nbp_working_day)
SELECT
    CONVERT(INT, FORMAT(dt,'yyyyMMdd')),
    dt,
    YEAR(dt),
    DATEPART(QUARTER,dt),
    MONTH(dt),
    DATENAME(MONTH,dt),
    DATEPART(ISO_WEEK,dt),
    ((DATEPART(WEEKDAY,dt)+5)%7)+1,                                   -- 1=Pon..7=Niedz
    CASE WHEN DATENAME(WEEKDAY,dt) IN ('Saturday','Sunday') THEN 1 ELSE 0 END,
    CASE
        WHEN DATENAME(WEEKDAY,dt) IN ('Saturday','Sunday') THEN 0
        -- stale swieta panstwowe PL (NBP nie notuje):
        WHEN (MONTH(dt)=1  AND DAY(dt)=1)  THEN 0   -- Nowy Rok
        WHEN (MONTH(dt)=1  AND DAY(dt)=6)  THEN 0   -- Trzech Kroli
        WHEN (MONTH(dt)=5  AND DAY(dt)=1)  THEN 0   -- Swieto Pracy
        WHEN (MONTH(dt)=5  AND DAY(dt)=3)  THEN 0   -- Konstytucja 3 Maja
        WHEN (MONTH(dt)=8  AND DAY(dt)=15) THEN 0   -- Wniebowziecie NMP
        WHEN (MONTH(dt)=11 AND DAY(dt)=1)  THEN 0   -- Wszystkich Swietych
        WHEN (MONTH(dt)=11 AND DAY(dt)=11) THEN 0   -- Niepodleglosci
        WHEN (MONTH(dt)=12 AND DAY(dt)=25) THEN 0   -- Boze Narodzenie
        WHEN (MONTH(dt)=12 AND DAY(dt)=26) THEN 0   -- drugi dzien
        ELSE 1
    END
FROM d
OPTION (MAXRECURSION 0);
GO
DECLARE @nDates INT = (SELECT COUNT(*) FROM dw.DIM_Date);
PRINT CONCAT('NFX_DW: DIM_Date wypelniona, wierszy = ', @nDates);
GO

/* Procedura: doprecyzuj is_nbp_working_day na podstawie faktycznych dat NBP.
   Dni z zakresu danych FX, dla ktorych NBP NIE opublikowal tabeli (a sa
   powszednie) -> oznacz jako nie-roboczy (np. ruchome swieta). */
IF OBJECT_ID('dw.usp_RefreshNbpWorkingDays') IS NOT NULL DROP PROCEDURE dw.usp_RefreshNbpWorkingDays;
GO
CREATE PROCEDURE dw.usp_RefreshNbpWorkingDays AS
BEGIN
    SET NOCOUNT ON;
    DECLARE @minD DATE, @maxD DATE;
    SELECT @minD = MIN(effective_date), @maxD = MAX(effective_date)
    FROM dw.FACT_ExchangeRates;
    IF @minD IS NULL RETURN;

    -- powszedni dzien w zakresie FX bez zadnej publikacji NBP = nie-roboczy
    UPDATE d SET d.is_nbp_working_day = 0
    FROM dw.DIM_Date d
    WHERE d.full_date BETWEEN @minD AND @maxD
      AND d.is_weekend = 0
      AND NOT EXISTS (SELECT 1 FROM dw.FACT_ExchangeRates f WHERE f.date_key = d.date_key);

    -- dzien z publikacja NBP = roboczy (na wszelki wypadek)
    UPDATE d SET d.is_nbp_working_day = 1
    FROM dw.DIM_Date d
    WHERE EXISTS (SELECT 1 FROM dw.FACT_ExchangeRates f WHERE f.date_key = d.date_key);
END
GO
PRINT 'NFX_DW: procedura usp_RefreshNbpWorkingDays gotowa.';
GO
