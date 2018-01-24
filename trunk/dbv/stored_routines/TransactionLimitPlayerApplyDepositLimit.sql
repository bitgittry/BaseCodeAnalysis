DROP procedure IF EXISTS `TransactionLimitPlayerApplyDepositLimit`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionLimitPlayerApplyDepositLimit`(clientStatID BIGINT, intervalType VARCHAR(20), sessionID BIGINT)
BEGIN
  DECLARE unlimitedAmount DECIMAL(18,5);
  DECLARE auditLogGroupId, clientID, userID BIGINT DEFAULT -1;
  SET @client_stat_id = clientStatID;
  SET @interval_type = intervalType;
  SET @session_id = sessionID;
  SET @future_start_date = now();
  SET unlimitedAmount = '99999999999.00000';
  
  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=@client_stat_id;
  SELECT user_id INTO userID FROM sessions_main WHERE session_id = @session_id;

  #getting the start date of the future deposit limit
  SET @future_start_date = (SELECT start_date FROM gaming_transfer_limit_clients
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=@client_stat_id AND 
    gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
  JOIN gaming_interval_type ON 
    gaming_interval_type.name=@interval_type AND 
    gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
  WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 0);
   
  IF(@future_start_date<=now()) THEN
        # Future Limit comes current
	    #Updating the current deposit limit to be inactive
		UPDATE gaming_transfer_limit_clients                                                
		JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
		JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
		SET gaming_transfer_limit_clients.is_active=0, gaming_transfer_limit_clients.session_id=@session_id 
		WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 1;
		
		#Updating the future start date of the limit to now
		UPDATE gaming_transfer_limit_clients                                                
		JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
		JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
		SET gaming_transfer_limit_clients.start_date = now()
		WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 0;
	ELSE
	     #Udating the current deposit limit end date
		SET @current_end_date = DATE_SUB(@future_start_date, interval 1 SECOND);
		UPDATE gaming_transfer_limit_clients                                                
		JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
		JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
		SET gaming_transfer_limit_clients.end_date = @current_end_date, gaming_transfer_limit_clients.session_id=@session_id
		WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 1;
		
  END IF;
  
		# Updating future deposit limit
		UPDATE gaming_transfer_limit_clients                                                
		JOIN gaming_client_stats ON 
		gaming_client_stats.client_stat_id=@client_stat_id AND 
		gaming_client_stats.client_stat_id=gaming_transfer_limit_clients.client_stat_id 
		JOIN gaming_interval_type ON 
		gaming_interval_type.name=@interval_type AND 
		gaming_interval_type.interval_type_id = gaming_transfer_limit_clients.interval_type_id
		SET gaming_transfer_limit_clients.is_confirmed =1, gaming_transfer_limit_clients.session_id=@session_id, gaming_transfer_limit_clients.is_active = IF(@future_start_date<=NOW() && gaming_transfer_limit_clients.limit_amount = unlimitedAmount, 0, 1), notification_processed_release = 1
		WHERE gaming_transfer_limit_clients.is_active=1 AND is_confirmed = 0;

        SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 4, 'User', NULL, NULL, clientID);

		CALL AuditLogAttributeChange(CONCAT(@interval_type, ' Future Deposit Limit Status'), clientID, auditLogGroupId, 'Confirmed', 'Awaiting Player Confirmation', NOW());
  
END$$

DELIMITER ;

