/* =====================================================================
   NFX – Nike Foreign Exchange  |  06_seed_dim_geography.sql
   Slownik 45 rynkow (kraje wystepujace w katalogu). Region = segment
   operacyjny Nike (North America / EMEA / Greater China / APLA).
   Waluta = waluta wiodaca rynku wyznaczona z danych (np. CZ/HU=EUR).
   ===================================================================== */
USE NFX_DW;
GO
DELETE FROM dw.DIM_Geography;   -- DELETE (nie TRUNCATE) bo tabela jest celem FK z FACT_Prices
GO
INSERT INTO dw.DIM_Geography (country_code, country_name, region, sub_region, currency_code) VALUES
 ('US','United States','North America','Northern America','USD'),
 ('CA','Canada','North America','Northern America','CAD'),
 ('MX','Mexico','APLA','Latin America','MXN'),
 ('CN','China (Mainland)','Greater China','Mainland China','CNY'),
 ('TW','Taiwan','Greater China','Taiwan','TWD'),
 ('JP','Japan','APLA','Japan','JPY'),
 ('KR','South Korea','APLA','South Korea','KRW'),
 ('SG','Singapore','APLA','Southeast Asia','SGD'),
 ('TH','Thailand','APLA','Southeast Asia','THB'),
 ('MY','Malaysia','APLA','Southeast Asia','MYR'),
 ('ID','Indonesia','APLA','Southeast Asia','IDR'),
 ('VN','Vietnam','APLA','Southeast Asia','VND'),
 ('PH','Philippines','APLA','Southeast Asia','PHP'),
 ('IN','India','APLA','South Asia','INR'),
 ('AU','Australia','APLA','Oceania','AUD'),
 ('NZ','New Zealand','APLA','Oceania','NZD'),
 ('GB','United Kingdom','EMEA','Western Europe','GBP'),
 ('IE','Ireland','EMEA','Western Europe','EUR'),
 ('FR','France','EMEA','Western Europe','EUR'),
 ('BE','Belgium','EMEA','Western Europe','EUR'),
 ('NL','Netherlands','EMEA','Western Europe','EUR'),
 ('LU','Luxembourg','EMEA','Western Europe','EUR'),
 ('DE','Germany','EMEA','Western Europe','EUR'),
 ('AT','Austria','EMEA','Western Europe','EUR'),
 ('CH','Switzerland','EMEA','Western Europe','CHF'),
 ('IT','Italy','EMEA','Southern Europe','EUR'),
 ('ES','Spain','EMEA','Southern Europe','EUR'),
 ('PT','Portugal','EMEA','Southern Europe','EUR'),
 ('GR','Greece','EMEA','Southern Europe','EUR'),
 ('SI','Slovenia','EMEA','Southern Europe','EUR'),
 ('HR','Croatia','EMEA','Southern Europe','EUR'),
 ('DK','Denmark','EMEA','Nordics','DKK'),
 ('SE','Sweden','EMEA','Nordics','SEK'),
 ('NO','Norway','EMEA','Nordics','NOK'),
 ('FI','Finland','EMEA','Nordics','EUR'),
 ('PL','Poland','EMEA','Central Europe','PLN'),
 ('CZ','Czechia','EMEA','Central Europe','EUR'),
 ('SK','Slovakia','EMEA','Central Europe','EUR'),
 ('HU','Hungary','EMEA','Central Europe','EUR'),
 ('RO','Romania','EMEA','Central Europe','RON'),
 ('BG','Bulgaria','EMEA','Central Europe','EUR'),
 ('TR','Turkey','EMEA','Middle East','TRY'),
 ('IL','Israel','EMEA','Middle East','ILS'),
 ('ZA','South Africa','EMEA','Africa','ZAR'),
 ('EG','Egypt','EMEA','Africa','EGP');
GO
DECLARE @nGeo INT = (SELECT COUNT(*) FROM dw.DIM_Geography);
PRINT CONCAT('NFX_DW: DIM_Geography wypelniona, krajow = ', @nGeo);
GO
