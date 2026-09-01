-- Route bchy1 TSIP / web mail to Al Moreno for remicsdev testing.
SET NOCOUNT ON;

DECLARE @email NVARCHAR(500) = N'alejandro.moreno@sympatico.ca';

UPDATE adm.account_details
SET email = @email
WHERE RTRIM(micsid) = 'bchy1';

UPDATE dbo.t_UserDetails
SET email = @email
WHERE RTRIM(micsid) = 'bchy1';

SELECT RTRIM(micsid) AS micsid, RTRIM(email) AS email, RTRIM(tsip_email) AS tsip_email
FROM adm.account_details
WHERE RTRIM(micsid) = 'bchy1';
