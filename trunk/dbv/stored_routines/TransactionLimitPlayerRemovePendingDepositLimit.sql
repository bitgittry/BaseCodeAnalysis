DROP procedure IF EXISTS `TransactionLimitPlayerRemovePendingDepositLimit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionLimitPlayerRemovePendingDepositLimit`(clientStatID BIGINT, intervalType VARCHAR(20), sessionID BIGINT)
BEGIN
 
	DECLARE auditLogGroupId, clientID, userID BIGINT DEFAULT -1;
	DECLARE currentValue DECIMAL(18, 5) DEFAULT NULL;
	SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID;

	SELECT limit_amount INTO currentValue FROM gaming_transfer_limit_clients
	JOIN gaming_client_stats ON 
	  gaming_client_stats.client_stat_id=clientStatID AND 
	  gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
	  gaming_interval_type.name=intervalType AND 
	  gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 0;

	UPDATE gaming_transfer_limit_clients
	JOIN gaming_client_stats ON 
	  gaming_client_stats.client_stat_id=clientStatID AND  
	  gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
	  gaming_interval_type.name=intervalType AND 
	  gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	SET gaming_transfer_limit_clients.is_active = 0, gaming_transfer_limit_clients.end_date = NOW()
	WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 0;

	SELECT user_id INTO userID FROM sessions_main WHERE session_id = sessionID;

	SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 4, 'User', NULL, NULL, clientID);

	CALL AuditLogAttributeChange(CONCAT(intervalType, ' ', 'Future Deposit Limit (Awaiting Player Confirmation)'), clientID, auditLogGroupId, NULL, currentValue, NOW());
END$$

DELIMITER ;

