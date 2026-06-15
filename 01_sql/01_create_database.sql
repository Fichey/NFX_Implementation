/* =====================================================================
   NFX – Nike Foreign Exchange  |  Hurtownia danych
   01_create_database.sql  –  Baza + schematy
   Cel: utworzyc baze NFX_DW i schematy logiczne (staging / dw).
   Uruchom jako pierwszy.  SQL Server 2019+.
   ===================================================================== */
IF DB_ID('NFX_DW') IS NULL
BEGIN
    CREATE DATABASE NFX_DW;
END
GO
ALTER DATABASE NFX_DW SET RECOVERY SIMPLE;   -- hurtownia: pelne logowanie zbedne
GO
USE NFX_DW;
GO
IF SCHEMA_ID('staging') IS NULL EXEC('CREATE SCHEMA staging;');   -- tabele przejsciowe (surowe + odrzucone)
GO
IF SCHEMA_ID('dw') IS NULL EXEC('CREATE SCHEMA dw;');             -- wymiary i fakty (gwiazda)
GO
IF SCHEMA_ID('bi') IS NULL EXEC('CREATE SCHEMA bi;');             -- widoki warstwy raportowej (OLAP/BI)
GO
PRINT 'NFX_DW: baza i schematy gotowe.';
GO
