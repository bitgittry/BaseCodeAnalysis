DROP procedure IF EXISTS `TransactionLimitPlayerRemoveDepositLimit`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionLimitPlayerRemoveDepositLimit`(clientStatID BIGINT, intervalType VARCHAR(20), ignoreTimeWindow TINYINT(1), sessionID BIGINT, modifierEntityType VARCHAR(45), increaseHours SMALLINT)
BEGIN

  DECLARE auditLogGroupId, clientID, userID, FutureDepositLimitID, currencyID BIGINT DEFAULT -1;
  DECLARE effectiveDate DATETIME DEFAULT NOW();
  DECLARE currentValue, futureValue, unlimitedValue DECIMAL(18, 5) DEFAULT NULL;
  DECLARE isFutureConfirmed, isConfirmed TINYINT DEFAULT 0;

  SET @client_stat_id = clientStatID;
  SET @interval_type = intervalType;
  SET @session_id = sessionID;
   
  SELECT user_id INTO userID FROM sessions_main WHERE session_id = @session_id;
  SELECT client_id, currency_id INTO clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=@client_stat_id;
  SELECT max_deposit INTO unlimitedValue FROM gaming_payment_amounts WHERE currency_id=currencyID;
 
  SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 4, modifierEntityType, NULL, NULL, clientID);

  IF(ignoreTimeWindow) THEN

	SELECT limit_amount INTO currentValue FROM gaming_transfer_limit_clients                                                
	JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	WHERE gaming_transfer_limit_clients.is_active=1 AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());

    #Removing current and future deposit limit now
	#Updating the current deposit limit
	UPDATE gaming_transfer_limit_clients                                                
	JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	SET gaming_transfer_limit_clients.is_active=NOT ignoreTimeWindow, gaming_transfer_limit_clients.end_date=NOW(), gaming_transfer_limit_clients.session_id=@session_id 
	WHERE gaming_transfer_limit_clients.is_active=1 AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());
	
	#Updating the future deposit limit, no matter if its confirmed or not

	SELECT limit_amount,is_confirmed INTO futureValue, isFutureConfirmed FROM gaming_transfer_limit_clients                                                
	JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	WHERE gaming_transfer_limit_clients.is_active=1 AND end_date IS NULL AND start_date > NOW();

	UPDATE gaming_transfer_limit_clients                                                
	JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	SET gaming_transfer_limit_clients.is_active=0, gaming_transfer_limit_clients.session_id=@session_id, end_date = NOW()
	#WHERE gaming_transfer_limit_clients.is_active=1 AND end_date IS NULL;
	WHERE gaming_transfer_limit_clients.is_active=1 AND end_date IS NULL AND start_date > NOW();

    -- Audit logs
	CALL AuditLogAttributeChange(CONCAT(@interval_type, ' ', 'Deposit Limit'), clientID, auditLogGroupId, NULL, currentValue, NOW());
    IF futureValue IS NOT NULL THEN
		CALL AuditLogAttributeChange(CONCAT(@interval_type, ' ', 'Future Deposit Limit', CASE WHEN isFutureConfirmed THEN ' (Awaiting Player Confirmation)' ELSE '' END), clientID, auditLogGroupId, NULL, futureValue, NOW());
	END IF;
  ELSE
	# Getting the future deposit limit
	SELECT transfer_limit_client_id, is_confirmed INTO FutureDepositLimitID, IsConfirmed
    FROM gaming_transfer_limit_clients
    JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id = clientStatID AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
	JOIN gaming_interval_type ON 
		gaming_interval_type.name = intervalType AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
	WHERE gaming_transfer_limit_clients.is_active=1 AND gaming_transfer_limit_clients.end_date IS NULL AND (gaming_transfer_limit_clients.is_confirmed = 0 OR (gaming_transfer_limit_clients.is_confirmed = 1 AND gaming_transfer_limit_clients.start_date > NOW()));
	
    IF (increaseHours = 0) THEN
		SET increaseHours = (SELECT value_int FROM gaming_settings WHERE name='DEPOSIT_LIMIT_INCREASE_OPERATOR_TIMEPERIOD_DAYS')*24;
	END IF;
	SET @start_date = DATE_ADD(NOW(), INTERVAL increaseHours HOUR);
    
    IF(FutureDepositLimitID != -1) THEN
		IF(IsConfirmed = 1) THEN 
			# Updating Current deposit limit
			UPDATE gaming_transfer_limit_clients                                                
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
			JOIN gaming_interval_type ON gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
			SET end_date = DATE_SUB(@start_date, interval 1 SECOND)
			WHERE gaming_transfer_limit_clients.is_active=1 AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()) AND is_confirmed = 1
				  AND gaming_client_stats.client_stat_id= clientStatID AND gaming_interval_type.name=intervalType;
		END IF;
		
		SELECT limit_amount,is_confirmed INTO futureValue, isFutureConfirmed FROM gaming_transfer_limit_clients             
		WHERE transfer_limit_client_id = FutureDepositLimitID;

        # Updating current future deposit limit
		UPDATE gaming_transfer_limit_clients                                                
		SET limit_amount = unlimitedValue, start_date = @start_date, session_id = sessionID, notification_processed_release = 0
		WHERE transfer_limit_client_id = FutureDepositLimitID;
	ELSE
		# New future unlimited deposit limit
		INSERT INTO gaming_transfer_limit_clients (interval_type_id, limit_amount, create_date, start_date, client_stat_id, is_active, session_id, notification_processed_release, is_confirmed)
		SELECT gaming_interval_type.interval_type_id, unlimitedValue, NOW(), @start_date, gaming_client_stats.client_stat_id, 1, sessionID, 0, IsConfirmed
		FROM gaming_client_stats                                                         
		JOIN gaming_interval_type ON 
		gaming_client_stats.client_stat_id = clientStatID AND
		gaming_interval_type.name = intervalType;

	
	 
	END IF;

-- Audit logs
    
	CALL AuditLogAttributeChange(CONCAT(@interval_type, ' ', 'Future Deposit Limit', CASE WHEN isFutureConfirmed THEN ' (Awaiting Player Confirmation)' ELSE '' END), clientID, auditLogGroupId, unlimitedValue, futureValue, @start_date);
  END IF;
END$$

DELIMITER ;

