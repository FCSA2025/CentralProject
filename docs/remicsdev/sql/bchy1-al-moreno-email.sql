-- Route all bchy* remicsdev mail to Al Moreno.
-- remicsdev Aux Eng / CASEDET KML / print-email look up adm.pcn_account_details first.
SET NOCOUNT ON;

DECLARE @email NVARCHAR(500) = N'alejandro.moreno@sympatico.ca';

UPDATE adm.account_details
SET email = @email
WHERE RTRIM(ultrixid) = 'bchy' OR RTRIM(micsid) LIKE 'bchy%';

UPDATE adm.pcn_account_details
SET email = @email
WHERE RTRIM(ultrixid) = 'bchy' OR RTRIM(micsid) LIKE 'bchy%';

UPDATE dbo.t_UserDetails
SET email = @email
WHERE RTRIM(micsId) LIKE 'bchy%';

SELECT 'adm.account_details' AS src, RTRIM(ultrixid) AS ultrixid, RTRIM(micsid) AS micsid, RTRIM(email) AS email
FROM adm.account_details
WHERE RTRIM(ultrixid) = 'bchy' OR RTRIM(micsid) LIKE 'bchy%'
UNION ALL
SELECT 'adm.pcn_account_details', RTRIM(ultrixid), RTRIM(micsid), RTRIM(email)
FROM adm.pcn_account_details
WHERE RTRIM(ultrixid) = 'bchy' OR RTRIM(micsid) LIKE 'bchy%'
UNION ALL
SELECT 'dbo.t_UserDetails', '', RTRIM(micsId), RTRIM(email)
FROM dbo.t_UserDetails
WHERE RTRIM(micsId) LIKE 'bchy%'
ORDER BY src, micsid;
