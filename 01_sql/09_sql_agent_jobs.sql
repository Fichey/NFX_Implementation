/* =====================================================================
   NFX – Nike Foreign Exchange | 09_sql_agent_jobs.sql
   Orkiestracja przez SQL Server Agent (Etap 3 planu).
   UWAGA: usluga SQLSERVERAGENT musi byc uruchomiona. W srodowisku
   implementacji byla zatrzymana (Manual) - skrypty dostarczamy jako
   konfiguracje gotowa do uruchomienia.

   Job #1 NikeETL_FX_Daily          - codziennie 07:00, pakiet FX za poprzedni dzien.
   Job #2 NikeETL_Catalogue_Quarterly - 1. dzien kwartalu / recznie, pakiet katalogu.

   W tej wersji kroki wolaja orkiestrator Python (run_etl.py). Jezeli
   wdrazasz pakiety .dtsx w SSISDB, podmien typ kroku na "SQL Server
   Integration Services Package".
   ===================================================================== */
USE msdb;
GO
------------------------------------------------------------------- JOB #1
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name='NikeETL_FX_Daily')
    EXEC dbo.sp_delete_job @job_name='NikeETL_FX_Daily';
GO
EXEC dbo.sp_add_job @job_name='NikeETL_FX_Daily',
     @description='NFX: codzienne pobranie kursow NBP (tab. A/B) i zaladowanie FACT_ExchangeRates';
EXEC dbo.sp_add_jobstep @job_name='NikeETL_FX_Daily',
     @step_name='Run FX ETL (incremental)',
     @subsystem='CMDEXEC',
     @command='"C:\Users\czare\AppData\Local\Programs\Python\Python311\python.exe" "C:\Users\czare\Desktop\studia\sem6\Hurtownie\NFX_Implementation\02_etl\run_etl.py" --mode incremental --skip-nike --fx-csv "C:\Users\czare\Desktop\studia\sem6\Hurtownie\NFX_Implementation\02_etl\stg_fx_rates.csv"',
     @retry_attempts=2, @retry_interval=5;
-- harmonogram: codziennie 07:00
EXEC dbo.sp_add_schedule @schedule_name='NFX_Daily_0700',
     @freq_type=4, @freq_interval=1, @active_start_time=070000;
EXEC dbo.sp_attach_schedule @job_name='NikeETL_FX_Daily', @schedule_name='NFX_Daily_0700';
EXEC dbo.sp_add_jobserver @job_name='NikeETL_FX_Daily';
GO
------------------------------------------------------------------- JOB #2
IF EXISTS (SELECT 1 FROM dbo.sysjobs WHERE name='NikeETL_Catalogue_Quarterly')
    EXEC dbo.sp_delete_job @job_name='NikeETL_Catalogue_Quarterly';
GO
EXEC dbo.sp_add_job @job_name='NikeETL_Catalogue_Quarterly',
     @description='NFX: kwartalne zaladowanie katalogu Nike (SCD2) + przeliczenie cen';
EXEC dbo.sp_add_jobstep @job_name='NikeETL_Catalogue_Quarterly',
     @step_name='Run Catalogue ETL (full)',
     @subsystem='CMDEXEC',
     @command='"C:\Users\czare\AppData\Local\Programs\Python\Python311\python.exe" "C:\Users\czare\Desktop\studia\sem6\Hurtownie\NFX_Implementation\02_etl\run_etl.py" --mode initial',
     @retry_attempts=1, @retry_interval=10;
-- harmonogram: 1. dzien miesiaca o 06:00 (kwartalnie uruchamia)
EXEC dbo.sp_add_schedule @schedule_name='NFX_Monthly_0600',
     @freq_type=16, @freq_interval=1, @freq_recurrence_factor = 3, @active_start_time=060000;
EXEC dbo.sp_attach_schedule @job_name='NikeETL_Catalogue_Quarterly', @schedule_name='NFX_Monthly_0600';
EXEC dbo.sp_add_jobserver @job_name='NikeETL_Catalogue_Quarterly';
GO
PRINT 'NFX: zadania SQL Server Agent skonfigurowane (wymaga uruchomionej uslugi SQLSERVERAGENT).';
GO

/* --- Alerting (opcjonalnie, wymaga skonfigurowanego Database Mail) ---
EXEC msdb.dbo.sp_add_alert @name='NFX_ETL_Failed',
     @severity=16, @notification_message='Pakiet NFX ETL zakonczyl sie bledem.';
-- powiadomienie e-mail przy odchyleniu liczby wierszy > 20% mozna zrealizowac
-- krokiem T-SQL porownujacym rows_in biezacego i poprzedniego wpisu staging.etl_run_log.
*/
