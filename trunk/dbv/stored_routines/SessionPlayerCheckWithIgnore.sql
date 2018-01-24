DROP procedure IF EXISTS `SessionPlayerCheckWithIgnore`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SessionPlayerCheckWithIgnore`(sessionGUID VARCHAR(80), serverID BIGINT, componentID BIGINT, ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), OUT statusCode INT)
root:BEGIN
  
  -- Added statuscode = 3 for kicked out player
  -- Fixed session expiry check issue with 2 minutes ignore  

  DECLARE userID,clientID,clientStatID,sessionID,currencyID,clientSegmentID, sessionClosedReasonId BIGINT DEFAULT -1;
  DECLARE currentExpiryDate, newExpiryDate DATETIME; 
  DECLARE currentBalance DECIMAL(18, 5);
  DECLARE currencyCode VARCHAR(3);
  DECLARE isSuspicious, isTestPlayer, isActiveSession TINYINT(1) DEFAULT 0;
  DECLARE sessionType VARCHAR(80) DEFAULT 'session_key';
  DECLARE tempSessionGUID, varUsername VARCHAR(80);
  DECLARE platformTypeID, channelTypeID INT DEFAULT NULL;

  SELECT value_string INTO sessionType FROM gaming_settings WHERE gaming_settings.name = 'PLAYER_SESSION_KEY_TYPE';	

  IF (sessionType='session_key') THEN
	  SELECT sessions_main.user_id, sessions_main.extra_id, sessions_main.extra2_id, sessions_main.session_id, date_expiry, IF(sessions_main.status_code=1 AND sessions_main.date_expiry > NOW() AND gaming_clients.is_active=1, 1, 0), session_close_type_id, sessions_main.platform_type_id
	  INTO userID, clientID, clientStatID, sessionID, currentExpiryDate, isActiveSession, sessionClosedReasonId, platformTypeID
	  FROM sessions_main FORCE INDEX (session_guid)
	  JOIN gaming_clients FORCE INDEX (PRIMARY) ON sessions_main.session_guid=sessionGUID AND sessions_main.active=1 AND sessions_main.session_type=2 AND 
		gaming_clients.client_id=sessions_main.extra_id;
  ELSE 
  
	  SELECT sessions_main.user_id, sessions_main.extra_id, sessions_main.extra2_id, sessions_main.session_id, date_expiry, 
        IF(sessions_main.status_code=1 AND sessions_main.date_expiry > NOW() AND gaming_clients.is_active=1, 1, 0),sessions_main.session_guid, session_close_type_id, sessions_main.platform_type_id
	  INTO userID, clientID, clientStatID, sessionID, currentExpiryDate, isActiveSession, tempSessionGUID, sessionClosedReasonId, platformTypeID
	  FROM gaming_clients FORCE INDEX (ext_client_id)
	  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_clients.client_id
	  JOIN sessions_main FORCE INDEX (client_latest_session) ON gaming_clients.ext_client_id=sessionGUID  
		AND sessions_main.extra_id=gaming_clients.client_id AND sessions_main.is_latest = 1 AND sessions_main.active=1 
	  WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL);
    
    SET ignoreSessionExpiry=1;
    
    SET sessionGUID = tempSessionGUID;
  END IF;
  
  IF(sessionClosedReasonId = (SELECT session_close_type_id FROM sessions_close_types WHERE name='UserKickout')) THEN
	SET statusCode = 3;
    LEAVE root;
  END IF;

  IF (clientID=-1 OR clientStatID=-1) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  IF (ignoreSessionExpiry=0 AND isActiveSession=0) THEN
    SELECT clientID AS client_id_for_fraud;
    SET statusCode = 1;
    LEAVE root;
  END IF;
  
  SELECT client_stat_id, (current_real_balance+current_bonus_balance+current_bonus_win_locked_balance) AS current_balance, gaming_currency.currency_code, 
    gaming_currency.currency_id, client_segment_id, is_suspicious, is_test_player, username 
  INTO clientStatID, currentBalance, currencyCode, currencyID, clientSegmentID, isSuspicious, isTestPlayer, varUsername
  FROM gaming_client_stats  
  JOIN gaming_clients ON
    gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.client_id=gaming_clients.client_id AND gaming_client_stats.is_active=1 
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id;
  
  IF (clientStatID = -1) THEN 
    SET statusCode = 2;
    LEAVE root;
  ELSE
  
    IF (extendSessionExpiry AND isActiveSession) THEN
    
      SELECT DATE_ADD(NOW(), INTERVAL sessions_defaults.expiry_duration MINUTE) INTO newExpiryDate 
      FROM sessions_defaults WHERE active=1 AND server_id=serverID AND component_id=componentID;
      
      IF (newExpiryDate>DATE_ADD(currentExpiryDate, INTERVAL 2 MINUTE)) THEN
		  UPDATE sessions_main FORCE INDEX (PRIMARY)
		  SET date_expiry=newExpiryDate 
		  WHERE session_id=sessionID AND active=1 AND status_code=1; 
      END IF;
      
    END IF;

	-- Get the Player channel
  	CALL PlatformTypesGetPlatformsByPlatformType(NULL, platformTypeID, platformTypeID, @platformType, channelTypeID, @channelType);
    
    SELECT clientID AS client_id, clientStatID AS client_stat_id, serverID AS server_id, sessionID AS session_id, sessionGUID AS session_guid, IF (extendSessionExpiry, newExpiryDate, currentExpiryDate) AS expiry_date,
           currentBalance AS current_balance, currencyCode AS currency_code, currencyID AS currency_id, clientSegmentID AS client_segment_id, isSuspicious AS is_suspicious, isTestPlayer AS is_test_player,
			platformTypeID AS platform_type_id, @platformType AS platform_type, channelTypeID AS channel_type_id, @channelType AS channel_type,
            current_real_balance - gaming_client_stats.current_ring_fenced_amount- gaming_client_stats.current_ring_fenced_sb
				- gaming_client_stats.current_ring_fenced_casino- gaming_client_stats.current_ring_fenced_poker AS current_real_balance,
			current_bonus_balance AS current_bonus_balance, current_bonus_win_locked_balance, IFNULL(FreeBets.free_bet_balance,0) AS free_bet_balance,
			gaming_client_stats.withdrawal_pending_amount, gaming_client_stats.current_loyalty_points, varUsername AS username,
            gaming_clients.is_kyc_checked
	FROM gaming_client_stats
    STRAIGHT_JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
    LEFT JOIN
	(
		SELECT SUM(gaming_bonus_instances.bonus_amount_remaining) AS free_bet_balance 
		FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses) 
		JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id 
		JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id=gaming_bonus_rules.bonus_type_awarding_id AND gaming_bonus_types_awarding.name='FreeBet'
		WHERE gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.is_active
	) AS FreeBets ON 1=1
    WHERE gaming_client_stats.client_stat_id=clientStatID;  
    
    SET statusCode = 0; 
  END IF;
  
END root$$

DELIMITER ;

