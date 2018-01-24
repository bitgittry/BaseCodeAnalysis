DROP procedure IF EXISTS `PlayerGetMinimalDetailsGeneral`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGetMinimalDetailsGeneral`(clientID BIGINT, clientStatID BIGINT, includeClosedAccounts TINYINT(1))
BEGIN
  
    DECLARE clientIdWherePart, clientStatIdWherePart, accountClosedWherePart, whereParts TEXT DEFAULT NULL;

	SET @clientID = clientID;
	SET @clientStatID = clientStatID;
 
	SET clientIdWherePart = IF(clientID <> 0 AND clientID IS NOT NULL, 'gaming_clients.client_id=@clientID', NULL);
	SET clientStatIdWherePart = IF(clientStatID <> 0 AND clientStatID IS NOT NULL, 'gaming_client_stats.client_stat_id=@clientStatID', NULL);

	IF (includeClosedAccounts IS NULL OR includeClosedAccounts <> 1) THEN
		SET @accountClosedWherePart = '(gaming_clients.is_account_closed=0 AND IFNULL(gaming_fraud_rule_client_settings.block_account, 0) = 0)';
	END IF;

	SET whereParts = CONCAT_WS(' AND ', clientIdWherePart, clientStatIdWherePart, accountClosedWherePart);

	SET @qry = CONCAT_WS(' ', '
		SELECT @client_id_returned := gaming_clients.client_id AS client_id, gaming_client_stats.client_stat_id, gaming_client_stats.currency_id, 
			gaming_currency.currency_code, gaming_clients.vip_level, gaming_clients.rnd_score, gaming_clients.ext_client_id, gaming_clients.username, gaming_clients.salt 
		FROM gaming_clients  
		STRAIGHT_JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id AND gaming_client_stats.is_active=1 
		STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id 
		LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id', 
	IF (whereParts IS NOT NULL, CONCAT('WHERE ', whereParts), ''), ';');

	PREPARE stmt FROM @qry;

	EXECUTE stmt;

	DEALLOCATE PREPARE stmt;

	-- IF needed be use @client_id_returned

	SET @clientID = NULL;
	SET @clientStatID = NULL;
	SET @client_id_returned = NULL;
	SET @qry = NULL;

END$$

DELIMITER ;

