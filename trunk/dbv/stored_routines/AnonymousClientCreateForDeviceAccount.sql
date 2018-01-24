DROP procedure IF EXISTS `AnonymousClientCreateForDeviceAccount`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `AnonymousClientCreateForDeviceAccount`(deviceAccountId BIGINT, OUT statusCode INT)
BEGIN
 
DECLARE vNOW DATETIME DEFAULT NOW();
DECLARE newClientId BIGINT;

INSERT INTO gaming_clients(username, sign_up_date, is_active, last_updated, gender) 
	SELECT CONCAT('anon',UUID()), vNOW, '1', vNOW, 'U';

SET newClientId = LAST_INSERT_ID();

INSERT INTO gaming_client_stats(client_id, currency_id, is_active) 
	SELECT newClientId, currency_id, 1 
FROM gaming_currency
WHERE currency_code = 'EUR';

INSERT INTO gaming_client_registrations(client_id, client_registration_type_id, created_date, is_current)
SELECT newClientId, client_registration_type_id, vNOW, 1 
	FROM gaming_client_registration_types 
WHERE registration_code = 'Anon'
ON DUPLICATE KEY UPDATE is_current = 1;

INSERT INTO gaming_clients_device_accounts(device_account_id, client_id, first_used_date, last_used_date) 
VALUES (deviceAccountId, newClientId, vNOW, vNOW);

INSERT INTO gaming_fraud_rule_client_settings(client_id) VALUES(newClientId);

SET statusCode = 0;

END$$

DELIMITER ;

