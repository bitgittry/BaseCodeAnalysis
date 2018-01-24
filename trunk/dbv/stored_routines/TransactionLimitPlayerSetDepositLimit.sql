DROP procedure IF EXISTS `TransactionLimitPlayerSetDepositLimit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionLimitPlayerSetDepositLimit`(
  clientStatID BIGINT, intervalType VARCHAR(20), varAmount DECIMAL(18, 5), ignoreTimeWindow TINYINT(1), sessionID BIGINT, 
  increaseHours SMALLINT, modifierEntityType VARCHAR(45), statusCode INT)
root: BEGIN

  -- Committing to DBV
  -- Optimized 
  
  DECLARE isFutureLimitAutomaticallyConfirmed TINYINT(1) DEFAULT 0;
  DECLARE increaseDays INT DEFAULT 0;
  DECLARE auditLogGroupId, clientID, userID, intervalTypeID BIGINT DEFAULT -1;
  DECLARE effectiveDate DATETIME DEFAULT NOW();
  DECLARE currentValue DECIMAL(18, 5) DEFAULT NULL;
  SET @interval_type = intervalType;
  SET @client_stat_id = clientStatID;
  SET @session_id = sessionID;
  SET @limit_amount = varAmount;
  
  SELECT interval_type_id INTO intervalTypeID FROM gaming_interval_type WHERE gaming_interval_type.name=@interval_type;
  
  SET @currenctAmount = 0;
  SET @rowCount = 0;
  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=@client_stat_id FOR UPDATE;
  
  SELECT @rowCount+1, limit_amount INTO @rowCount, @currenctAmount  
  FROM gaming_transfer_limit_clients FORCE INDEX (client_active)
  WHERE
	gaming_transfer_limit_clients.client_stat_id=@client_stat_id AND 
    gaming_transfer_limit_clients.is_active=1 AND gaming_transfer_limit_clients.interval_type_id=intervalTypeID AND 
	start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());
  
  SET @ApplyInNextTimePeriod = 0;
  IF (@rowCount = 1) THEN
    IF (varAMount > @currenctAmount) THEN
      SET @ApplyInNextTimePeriod = 1;
    END IF;
  ELSE 
    
    IF (@rowCount > 1) THEN
      SET statusCode=1;
      LEAVE root;
    END IF;
  END IF;
  
  SET @ApplyInNextTimePeriod=(@ApplyInNextTimePeriod AND NOT ignoreTimeWindow);
  
  
  IF (@ApplyInNextTimePeriod = 1) THEN
	
    IF (increaseHours = 0) THEN
		SET increaseHours = (SELECT value_int FROM gaming_settings WHERE name='DEPOSIT_LIMIT_INCREASE_OPERATOR_TIMEPERIOD_DAYS')*24;
        SET isFutureLimitAutomaticallyConfirmed = 1;
    END IF;
    
    SET @end_date = DATE_ADD(NOW(), INTERVAL increaseHours HOUR);
    
	UPDATE gaming_transfer_limit_clients FORCE INDEX (client_active)                                                
    SET end_date= IF(isFutureLimitAutomaticallyConfirmed, @end_date, null), gaming_transfer_limit_clients.session_id=@session_id 
    WHERE gaming_transfer_limit_clients.client_stat_id=@client_stat_id 
		AND gaming_transfer_limit_clients.is_active=1 AND gaming_transfer_limit_clients.interval_type_id=intervalTypeID
		AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW());
    
    -- Retrieving old future deposit limit value
    SELECT limit_amount INTO currentValue 
    FROM gaming_transfer_limit_clients FORCE INDEX (client_active)                                              
    WHERE gaming_transfer_limit_clients.client_stat_id=@client_stat_id 
		AND gaming_transfer_limit_clients.is_active=1  AND gaming_transfer_limit_clients.interval_type_id=intervalTypeID
		AND end_date IS NULL AND (is_confirmed = 0 OR (is_confirmed = 1 AND start_date > NOW()));

    # Making future deposit limits inactive
    UPDATE gaming_transfer_limit_clients FORCE INDEX (client_active)                                               
    SET gaming_transfer_limit_clients.is_active=0, gaming_transfer_limit_clients.session_id=@session_id 
    WHERE gaming_transfer_limit_clients.client_stat_id=@client_stat_id 
		AND gaming_transfer_limit_clients.is_active=1  AND gaming_transfer_limit_clients.interval_type_id=intervalTypeID 
		AND end_date IS NULL AND (is_confirmed = 0 OR (is_confirmed = 1 AND start_date > NOW()));
  
    SET @start_date=DATE_ADD(@end_date, INTERVAL 1 SECOND);
    SET effectiveDate = @start_date;

    INSERT INTO gaming_transfer_limit_clients (
		interval_type_id, limit_amount, create_date, 
		start_date, client_stat_id, is_active, session_id, notification_processed_release, is_confirmed)
    SELECT intervalTypeID, @limit_amount, NOW(), @start_date, @client_stat_id, 1, @session_id, 0, isFutureLimitAutomaticallyConfirmed;
      
  ELSE
  
    --  Retrieving old VALUE
	SELECT limit_amount INTO currentValue 
    FROM gaming_transfer_limit_clients FORCE INDEX (client_active)                                               
    WHERE gaming_transfer_limit_clients.client_stat_id=@client_stat_id 
		AND gaming_transfer_limit_clients.is_active=1 AND gaming_transfer_limit_clients.interval_type_id=intervalTypeID
		AND start_date <= NOW() AND (end_date IS NULL OR end_date >= NOW()); 
     
    UPDATE gaming_transfer_limit_clients FORCE INDEX (client_active)                                                
    SET gaming_transfer_limit_clients.is_active=0, gaming_transfer_limit_clients.session_id=@session_id 
    WHERE gaming_transfer_limit_clients.client_stat_id=@client_stat_id 
		AND gaming_transfer_limit_clients.is_active=1  AND gaming_transfer_limit_clients.interval_type_id=intervalTypeID; 
  
    INSERT INTO gaming_transfer_limit_clients (interval_type_id, limit_amount, create_date, start_date, client_stat_id, is_active, session_id, is_confirmed)
    SELECT intervalTypeID, @limit_amount, NOW(), NOW(), @client_stat_id, 1, @session_id, 1;
   
  END IF;
  
  SELECT user_id INTO userID FROM sessions_main WHERE session_id = @session_id;

  SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 4, modifierEntityType, NULL, NULL, clientID);

  CALL AuditLogAttributeChange(CONCAT(@interval_type, ' ', CASE WHEN @ApplyInNextTimePeriod = 1 THEN 'Future ' ELSE '' END, 'Deposit Limit', CASE WHEN @ApplyInNextTimePeriod THEN ' (Awaiting Player Confirmation)' ELSE '' END), clientID, auditLogGroupId, varAmount, currentValue, effectiveDate);

  SET statusCode=0;
  
END root$$

DELIMITER ;

