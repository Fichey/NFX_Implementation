SET NOCOUNT ON;
PRINT '=== 1. Tryb uwierzytelniania (0=Mixed/SQL+Windows, 1=tylko Windows) ===';
SELECT SERVERPROPERTY('IsIntegratedSecurityOnly') AS IsWindowsOnly,
       SERVERPROPERTY('ServerName') AS ServerName,
       @@SERVERNAME AS AtAtServerName;

PRINT '=== 2. Nasluch TCP/IP (Power BI laczy sie po TCP) ===';
SELECT listener_id, ip_address, port, state_desc, is_ipv4
FROM sys.dm_tcp_listener_states WHERE type=0;  -- 0 = TSQL

PRINT '=== 3. Loginy SQL (SQL authentication) ===';
SELECT name, is_disabled, type_desc, create_date
FROM sys.server_principals
WHERE type='S' AND name NOT LIKE '##%'
ORDER BY name;

PRINT '=== 4. Czy loginy SQL maja dostep (uzytkownika) w bazie NFX_DW ===';
SELECT dp.name AS db_user, sp.name AS server_login, dp.type_desc
FROM NFX_DW.sys.database_principals dp
JOIN sys.server_principals sp ON sp.sid = dp.sid
WHERE sp.type='S';
