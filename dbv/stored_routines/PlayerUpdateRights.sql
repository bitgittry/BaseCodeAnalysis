DROP procedure IF EXISTS `PlayerUpdateRights`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerUpdateRights`(clientID BIGINT, isActive TINYINT(1), isAccountClosed TINYINT(1), isSuspicious TINYINT(1), 
isTestPlayer TINYINT(1), testPlayerAllowTransfers TINYINT(1), isPlayAllowed TINYINT(1), isAffiliate TINYINT(1), exceededLoginAtempts TINYINT(1), bonusSeeker TINYINT(1), 
bonusDontWant TINYINT(1), depositAllowed TINYINT(1), withdrawalAllowed TINYINT(1), sessionID BIGINT, userID BIGINT, riskScore DECIMAL(22,9), clientAccessChangeTypeID INT, 
accountClosedLevel INT, reason VARCHAR(512), isVipDowngradeDisabled TINYINT(1), allowLoginBannedCountryFromIP TINYINT(1), modifierEntityType VARCHAR(45), closureReviewDate DATETIME, OUT statusCode INT)
root: BEGIN
  -- Resetting temporary_locking_bad_attempts if exceededLoginAtempts is set to 0 
  -- Added Notifications 
  -- Prospect and Partially Registered Players cannot have their Account Activated
  -- Added saving new audit logs 
  DECLARE clientIDCheck, clientStatID, realMoneyTransactions, auditLogGroupId BIGINT DEFAULT -1;
  DECLARE curIsActive, curIsAccountClosed, curIsSuspicious, curIsTestPlayer, curIsAffiliate, curExceededLoginAmount, curBonusSeeker, curBonusDontWant, curDepositAllowed, 
	curWithdrawalAllowed, curIsVipDowngradeDisabled, curIsPlayAllowed, curTestPlayerAllowTransfers, curAccountClosedLevel, curAllowLoginBannedCountryFromIP TINYINT(1) DEFAULT 0;
  DECLARE HasActivity, AllowTransfersNotTestPlayer, notificationEnabled, uniqueUsername, uniqueEmail, uniqueNickname, uniqueMobile, usernameCaseSensitive TINYINT DEFAULT 0;
  DECLARE curRiskScore  DECIMAL(22,9);
  DECLARE emailVar, mobVar, usernameVar, nicknameVar VARCHAR(80);
  DECLARE registrationType VARCHAR(5); 
  DECLARE numEmail, numUsername, numMob, numNickname BIGINT DEFAULT 0;
  DECLARE curClosureReviewDate DATETIME;
  DECLARE mustUpdateClosureReviewDate TINYINT(1) DEFAULT 0;

  SELECT gs1.value_bool INTO notificationEnabled FROM gaming_settings gs1 WHERE gs1.name='NOTIFICATION_ENABLED';
  SELECT value_bool INTO @USERNAME_CASE_SENSITIVE FROM gaming_settings WHERE name='USERNAME_CASE_SENSITIVE';

  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_id=clientID AND is_active LIMIT 1 FOR UPDATE;
 
  SELECT gaming_clients.client_id, gaming_clients.is_active, is_account_closed, is_suspicious, is_test_player, is_affiliate, email, mob, username, nickname,exceeded_login_attempts, bonus_seeker, bonus_dont_want, deposit_allowed,
 withdrawal_allowed, vip_downgrade_disabled, risk_score, is_play_allowed, test_player_allow_transfers, account_closed_level, gaming_client_registration_types.registration_code, allow_login_banned_country_ip, closure_review_date
  INTO clientIDCheck, curIsActive, curIsAccountClosed, curIsSuspicious, curIsTestPlayer, curIsAffiliate, emailVar, mobVar, usernameVar, nicknameVar, curExceededLoginAmount, curBonusSeeker, curBonusDontWant, curDepositAllowed, 
	curWithdrawalAllowed, curIsVipDowngradeDisabled, curRiskScore, curIsPlayAllowed, curTestPlayerAllowTransfers, curAccountClosedLevel, registrationType, curAllowLoginBannedCountryFromIP, curClosureReviewDate
  FROM gaming_clients
  JOIN gaming_client_registrations ON gaming_client_registrations.client_id = gaming_clients.client_id
  JOIN gaming_client_registration_types ON gaming_client_registration_types.client_registration_type_id = gaming_client_registrations.client_registration_type_id AND gaming_client_registrations.is_current = 1
  WHERE gaming_clients.client_id=clientID;

  IF (clientIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF(closureReviewDate IS NOT NULL) THEN
    SET mustUpdateClosureReviewDate = 1;
  END IF;							

  IF (isAccountClosed IS NOT NULL AND isAccountClosed=1) THEN
    SET isAccountClosed=1;
    SET isActive=0;    
	SET closureReviewDate=NULL;
    SET mustUpdateClosureReviewDate = 1;								 
  END IF;



  -- If there is a change in test players allow transfers. Check if the player is test player first
  SELECT IF (gaming_clients.test_player_allow_transfers != testPlayerAllowTransfers AND gaming_clients.is_test_player = 0, 1, 0)
  INTO AllowTransfersNotTestPlayer 
  FROM gaming_clients
  WHERE gaming_clients.client_id = clientID;

  IF (AllowTransfersNotTestPlayer=1) THEN
		SET statusCode=5;
		LEAVE root;
  END IF;


  -- If there is a change in test player - 1/0 first check if there is any transaction of the client. If so return error
  SELECT IF (gaming_clients.is_test_player != isTestPlayer AND (IF(total_real_played!=0,1,0) OR IF((total_bonus_transferred + total_bonus_win_locked_transferred)!=0,1,0) OR IF(total_adjustments!=0,1,0)
			OR IF(deposited_amount!=0,1,0) OR IF(current_real_balance!=0,1,0)),1,0)
  INTO HasActivity
  FROM gaming_client_stats 
  JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
  WHERE client_stat_id = clientStatID;

  IF (HasActivity=1) THEN
		SET statusCode=3;
		LEAVE root;
  END IF;
  
  IF (curIsAccountClosed=1 AND isAccountClosed=0) THEN
	SELECT gfd1.is_unique, gfd2.is_unique, gfd3.is_unique, gfd4.is_unique INTO uniqueUsername, uniqueEmail, uniqueNickname, uniqueMobile
	FROM gaming_field_definitions gfd1
	STRAIGHT_JOIN gaming_field_definitions gfd2 ON gfd2.field_definition_type_id = gfd1.field_definition_type_id AND gfd2.field_name = 'EmailAddress'
	STRAIGHT_JOIN gaming_field_definitions gfd3 ON gfd3.field_definition_type_id = gfd1.field_definition_type_id AND gfd3.field_name = 'Nickname'
	STRAIGHT_JOIN gaming_field_definitions gfd4 ON gfd4.field_definition_type_id = gfd1.field_definition_type_id AND gfd4.field_name = 'MobilePhone'
	where gfd1.field_definition_type_id = 2 AND gfd1.field_name = 'Username';
	
	IF (uniqueEmail) THEN
		SELECT COUNT(*) INTO numEmail FROM gaming_clients WHERE email=emailVar AND is_account_closed=0; 
	END IF;
	
	IF (uniqueUsername) THEN
		SELECT COUNT(*) INTO numUsername FROM gaming_clients WHERE gaming_clients.username=usernameVar AND IF (usernameCaseSensitive=1, BINARY gaming_clients.username = usernameVar, LOWER(username) = BINARY LOWER(usernameVar)) AND is_account_closed=0;
    END IF;

	IF (uniqueNickname) THEN
		SELECT COUNT(*) INTO numNickname FROM gaming_clients WHERE nickname=nicknameVar AND is_account_closed=0; 
	END IF;

	IF (uniqueMobile) THEN
		SELECT COUNT(*) INTO numMob FROM gaming_clients WHERE mob=mobVar AND is_account_closed=0; 
	END IF;

    IF (numEmail>0 OR numUsername>0 OR numNickname>0 OR numMob>0) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;

  END IF;
  
  IF (curExceededLoginAmount=1 AND exceededLoginAtempts=0) THEN
    UPDATE gaming_clients_login_attempts_totals
    SET last_consecutive_bad=0, temporary_locking_bad_attempts=0
    WHERE client_id=clientID;
	
	-- PermanentLoginRestrictionRelease
	IF (notificationEnabled=1) THEN
		INSERT INTO notifications_events (notification_event_type_id, event_id, is_processing) 
		VALUES (505, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	END IF;
  END IF;

  IF (curExceededLoginAmount=0 AND exceededLoginAtempts=1) THEN
	-- PermanentLoginRestrictionSet
	IF (notificationEnabled=1) THEN
		INSERT INTO notifications_events (notification_event_type_id, event_id, is_processing) 
		VALUES (504, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
	END IF;
  END IF;

  IF (notificationEnabled=1 AND curIsActive=1 AND isActive=0) THEN 
	INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
	VALUES (520, clientID, userID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
  END IF;
  
  -- Change state of test_player_allow_transfers when Deactivating testplayer.
  IF(testPlayerAllowTransfers IS NULL AND isTestPlayer IS NOT NULL AND isTestPlayer = 0) THEN 
	SET testPlayerAllowTransfers = 0;
  END IF; 

  UPDATE gaming_clients
  SET 
    is_active=IFNULL(isActive,is_active), is_account_closed=IFNULL(isAccountClosed,is_account_closed), account_closed_date=IF(NOT curIsAccountClosed AND isAccountClosed, NOW(), IF (curIsAccountClosed AND isAccountClosed, account_closed_date, NULL)),
    is_suspicious=IFNULL(isSuspicious, is_suspicious), is_test_player=IF(IFNULL(isTestPlayer,is_test_player) OR IFNULL(testPlayerAllowTransfers,test_player_allow_transfers),1,0), test_player_allow_transfers=IFNULL(testPlayerAllowTransfers, test_player_allow_transfers), 
    is_play_allowed=IFNULL(isPlayAllowed,is_play_allowed), is_affiliate=IFNULL(isAffiliate, is_affiliate), session_id=sessionID, last_updated_flags=NOW(),
    exceeded_login_attempts=IFNULL(exceededLoginAtempts,exceeded_login_attempts), bonus_seeker=IFNULL(bonusSeeker,bonus_seeker), bonus_dont_want=IFNULL(bonusDontWant, bonus_dont_want),
	deposit_allowed=IFNULL(depositAllowed,deposit_allowed), withdrawal_allowed=IFNULL(withdrawalAllowed, withdrawal_allowed), risk_score=IFNULL(riskScore, risk_score), account_closed_level=IFNULL(accountClosedLevel, account_closed_level),
    vip_downgrade_disabled = IFNULL(isVipDowngradeDisabled,vip_downgrade_disabled), allow_login_banned_country_ip=IFNULL(allowLoginBannedCountryFromIP,allow_login_banned_country_ip), closure_review_date=IF(mustUpdateClosureReviewDate = 1, closureReviewDate, closure_review_date)
  WHERE client_id=clientID;


	IF((isActive IS NOT NULL AND isActive = 0) OR (isAccountClosed IS NOT NULL AND isAccountClosed = 1)) THEN
		UPDATE gaming_balance_accounts gba SET gba.is_active = 0 WHERE gba.client_stat_id = clientStatID;
	END IF;

  
  IF ((bonusSeeker IS NOT NULL AND bonusSeeker!=curBonusSeeker) OR (bonusDontWant IS NOT NULL AND bonusDontWant!=curBonusDontWant)) THEN
	CALL PlayerSelectionUpdatePlayerCacheForceUpdate(clientStatID);
  END IF;

  
  INSERT INTO gaming_client_access_changes (client_id, user_id, timestamp, client_access_change_type_id, reason, is_active, is_suspicious, deposit_allowed, withdrawal_allowed, 
	is_play_allowed, is_affiliate, is_test_player, test_player_allow_transfers, is_account_closed, bonus_seeker, bonus_dont_want, exceeded_login_attempts, risk_score, account_closed_level, vip_downgrade_disabled, allow_login_banned_country_ip)
  VALUES
	(clientID, userID, now(), clientAccessChangeTypeID, reason, isActive, isSuspicious, depositAllowed, withdrawalAllowed, isPlayAllowed, isAffiliate, isTestPlayer, 
	 testPlayerAllowTransfers, isAccountClosed, bonusSeeker, bonusDontWant, exceededLoginAtempts, riskScore, accountClosedLevel, isVipDowngradeDisabled, allowLoginBannedCountryFromIP);

  -- New version of audit logs

  SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, clientID, 1, modifierEntityType, clientAccessChangeTypeID, reason, clientID);
 
	IF(isActive IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Is Active', clientID, auditLogGroupId, CASE isActive WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsActive WHEN 1 THEN 'YES' ELSE 'NO' END, now());
    END IF;
	IF(isSuspicious IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Is Suspicious', clientID, auditLogGroupId, CASE isSuspicious WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsSuspicious WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(depositAllowed IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Deposit Allowed', clientID, auditLogGroupId, CASE depositAllowed WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curDepositAllowed WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(withdrawalAllowed IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Withdrawal Allowed', clientID, auditLogGroupId, CASE withdrawalAllowed WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curWithdrawalAllowed WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(isPlayAllowed IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Is Play Allowed', clientID, auditLogGroupId, CASE isPlayAllowed WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsPlayAllowed WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(isAffiliate IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Is Affiliate', clientID, auditLogGroupId, CASE isAffiliate WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsAffiliate WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(isTestPlayer IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Is Test Player', clientID, auditLogGroupId, CASE isTestPlayer WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsTestPlayer WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(testPlayerAllowTransfers IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Test Player Allow Transfers', clientID, auditLogGroupId, CASE testPlayerAllowTransfers WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curTestPlayerAllowTransfers WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(isAccountClosed IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Is Account Closed', clientID, auditLogGroupId, CASE isAccountClosed WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsAccountClosed WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(bonusSeeker IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Bonus Seeker', clientID, auditLogGroupId, CASE bonusSeeker WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curBonusSeeker WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(bonusDontWant IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Bonus Dont Want', clientID, auditLogGroupId, CASE bonusDontWant WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curBonusDontWant WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(exceededLoginAtempts IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Exceeded Login Attempts', clientID, auditLogGroupId, CASE exceededLoginAtempts WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curExceededLoginAmount WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
	IF(riskScore IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Risk Score', clientID, auditLogGroupId, riskScore, curRiskScore, now());
	END IF;
	IF(accountClosedLevel IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Account Closed Level', clientID, auditLogGroupId, accountClosedLevel, curAccountClosedLevel, now());
	END IF;
	IF(isVipDowngradeDisabled IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Vip Downgrade Disabled', clientID, auditLogGroupId, CASE isVipDowngradeDisabled WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curIsVipDowngradeDisabled WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;
  IF(allowLoginBannedCountryFromIP IS NOT NULL) THEN
		CALL AuditLogAttributeChange('Allow Login Banned Country Ip', clientID, auditLogGroupId, CASE allowLoginBannedCountryFromIP WHEN 1 THEN 'YES' ELSE 'NO' END, CASE curAllowLoginBannedCountryFromIP WHEN 1 THEN 'YES' ELSE 'NO' END, now());
	END IF;

  IF (curIsAccountClosed=0 AND isAccountClosed=1) then
	DELETE FROM gaming_clients_unique_field_combination_hashes WHERE client_id = clientID;
  END IF;

  SET statusCode=0;


END root$$

DELIMITER ;

