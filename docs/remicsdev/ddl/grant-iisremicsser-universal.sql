-- Universal UseDbAuth rights for the IIS app-pool service account.
-- Do not grant per test schema (rctl / dnd / xci). New company schemas
-- inherit these database-level roles without another grant pass.
--
-- Safe to re-run. Target: remicsdev now; same script on production when
-- UseDbAuth is enabled there.

SET NOCOUNT ON;

IF NOT EXISTS (SELECT 1 FROM sys.database_principals WHERE name = N'CLOUDMICSDEV\IISReMicsSer')
BEGIN
    CREATE USER [CLOUDMICSDEV\IISReMicsSer] FOR LOGIN [CLOUDMICSDEV\IISReMicsSer];
END

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
    WHERE r.name = N'db_ddladmin' AND m.name = N'CLOUDMICSDEV\IISReMicsSer'
)
    ALTER ROLE db_ddladmin ADD MEMBER [CLOUDMICSDEV\IISReMicsSer];

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
    WHERE r.name = N'db_datareader' AND m.name = N'CLOUDMICSDEV\IISReMicsSer'
)
    ALTER ROLE db_datareader ADD MEMBER [CLOUDMICSDEV\IISReMicsSer];

IF NOT EXISTS (
    SELECT 1
    FROM sys.database_role_members rm
    JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
    JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
    WHERE r.name = N'db_datawriter' AND m.name = N'CLOUDMICSDEV\IISReMicsSer'
)
    ALTER ROLE db_datawriter ADD MEMBER [CLOUDMICSDEV\IISReMicsSer];

GRANT ALTER ANY SCHEMA TO [CLOUDMICSDEV\IISReMicsSer];
GRANT CREATE TABLE TO [CLOUDMICSDEV\IISReMicsSer];
GRANT CREATE VIEW TO [CLOUDMICSDEV\IISReMicsSer];
GRANT EXECUTE TO [CLOUDMICSDEV\IISReMicsSer];
GRANT SELECT, UPDATE ON OBJECT::dbo.t_UserDetails TO [CLOUDMICSDEV\IISReMicsSer];
GRANT SELECT ON SCHEMA::adm TO [CLOUDMICSDEV\IISReMicsSer];
GRANT EXECUTE ON OBJECT::dbo.getnextsession TO [CLOUDMICSDEV\IISReMicsSer];
GRANT EXECUTE ON OBJECT::dbo.user_project2022 TO [CLOUDMICSDEV\IISReMicsSer];
GRANT EXECUTE ON OBJECT::dbo.user_schema2022 TO [CLOUDMICSDEV\IISReMicsSer];

SELECT
    r.name AS role_name,
    m.name AS member_name
FROM sys.database_role_members rm
JOIN sys.database_principals r ON r.principal_id = rm.role_principal_id
JOIN sys.database_principals m ON m.principal_id = rm.member_principal_id
WHERE m.name = N'CLOUDMICSDEV\IISReMicsSer'
ORDER BY r.name;
