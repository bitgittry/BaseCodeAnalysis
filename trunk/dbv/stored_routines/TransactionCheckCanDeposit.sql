DROP procedure IF EXISTS `TransactionCheckCanDeposit`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionCheckCanDeposit`(clientStatID BIGINT, paymentMethodName VARCHAR(80), varAmount DECIMAL(18, 5), stopDeposit TINYINT(1), performPaymentMethodChecks TINYINT(1), OUT statusCode INT)
root: BEGIN

      
  

  DECLARE paymentMethodID, paymentMethodGroupID, clientID, clientIDCheck BIGINT DEFAULT -1;
  DECLARE checkDepositLimitReturn, errorCode INT DEFAULT 0;
  DECLARE beforeKYCDepositLimitEnabled, kycRequiredPerPlayerAccount, kycLimitExceeded, invalidBonusCode, canDeposit TINYINT(1) DEFAULT 0;
 
  DECLARE isSuspicious, depositAllowed, isTestPlayer, requireClientInfo, isEntered, isValidated, isDisabled, fraudEnabled, fraudOnDepositEnabled, dissallowTransfer, playerRestrictionEnabled, testPlayerAllowTransfers, accountActivated, maxBalanceThresholdEnabled TINYINT(1) DEFAULT 0;
 
  DECLARE paymentGroupDepositAllowed TINYINT(1) DEFAULT 1;
  DECLARE paymentGatewayMethodSubName VARCHAR(80) DEFAULT NULL;
 
  DECLARE currentRealBalance, maxPlayerBalanceThreshold DECIMAL(18,5)  DEFAULT 0;
  
  SELECT value_bool INTO maxBalanceThresholdEnabled FROM gaming_settings WHERE name='MAXIMUM_PLAYER_EWALLET_BALANCE_THRESHOLD_ENABLED';
 
  SET statusCode=0; 
   
  SELECT gaming_clients.client_id, is_suspicious, deposit_allowed, is_test_player, test_player_allow_transfers, gaming_clients.account_activated, gaming_client_stats.current_real_balance, ifnull(gaming_client_stats.max_player_balance_threshold,gaming_countries.max_player_balance_threshold) as max_player_balance_threshold
  INTO clientID, isSuspicious, depositAllowed, isTestPlayer, testPlayerAllowTransfers, accountActivated, currentRealBalance, maxPlayerBalanceThreshold
  FROM gaming_clients 
  JOIN gaming_client_stats ON 
    gaming_client_stats.client_stat_id=clientStatID AND
    gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1
  LEFT JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id AND clients_locations.is_primary = 1  
  LEFT JOIN gaming_countries ON clients_locations.country_id = gaming_countries.country_id ; 
  
  IF (clientID=-1 OR (isSuspicious=1 OR depositAllowed=0 OR (isTestPlayer=1 AND testPlayerAllowTransfers=0))) THEN
    SET statusCode=7;
  END IF; 
  
  IF (statusCode=0 AND stopDeposit) THEN
  SET statusCode = 11;
  END IF;
 
 
  IF(maxBalanceThresholdEnabled = 1 AND NOT ISNULL(maxPlayerBalanceThreshold) AND (maxPlayerBalanceThreshold = 0 OR (currentRealBalance + varAmount > maxPlayerBalanceThreshold))) THEN
  SET statusCode = 12;
    LEAVE root;
  END IF;
 
  SELECT IF(is_sub_method=0, payment_method_id, parent_payment_method_id), payment_method_group_id, payment_gateway_method_sub_name, can_deposit
    INTO paymentMethodID, paymentMethodGroupID, paymentGatewayMethodSubName, canDeposit
  FROM gaming_payment_method
  WHERE gaming_payment_method.name=paymentMethodName
  LIMIT 1;

  IF(canDeposit = 0 AND paymentMethodID<>-1) THEN
	SET statusCode=13;
  END IF;

  IF (statusCode=0 AND paymentMethodID=-1) THEN
    SET statusCode=1;
  END IF;
  
 
  IF (statusCode=0) THEN
    SELECT gaming_payment_method.require_client_info, is_entered, is_validated, is_disabled
    INTO requireClientInfo, isEntered, isValidated, isDisabled
    FROM gaming_client_payment_info
    JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_payment_info.client_id=gaming_client_stats.client_id
    JOIN gaming_payment_method ON gaming_payment_method.payment_method_id=paymentMethodID AND gaming_client_payment_info.payment_method_id=gaming_payment_method.payment_method_id;
  
    IF (isDisabled) THEN
      SET statusCode=2;
    END IF;
    
    IF (statusCode=0 AND requireClientInfo AND isEntered=0) THEN
      SET statusCode=3;
    END IF;
  END IF;
  
  
  SELECT value_bool INTO fraudEnabled FROM gaming_settings WHERE name='FRAUD_ENABLED';
  SELECT value_bool INTO fraudOnDepositEnabled FROM gaming_settings WHERE name='FRAUD_ON_DEPOSIT_ENABLED';
  IF (statusCode=0 AND fraudEnabled=1 AND fraudOnDepositEnabled=1) THEN
    
    SET clientIDCheck=-1;
    SET dissallowTransfer=0;
  SET paymentGroupDepositAllowed=1;
  
    SELECT client_id, disallow_transfers, IF(performPaymentMethodChecks,IFNULL(deposit_allowed,1),1) INTO clientIDCheck, dissallowTransfer, paymentGroupDepositAllowed
    FROM gaming_fraud_client_events AS cl_events
    JOIN gaming_fraud_classification_types ON 
      cl_events.client_id=clientID AND cl_events.is_current=1 AND
      cl_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id
    LEFT JOIN gaming_fraud_classification_payment_groups gfcpg ON 
      gaming_fraud_classification_types.fraud_classification_type_id = gfcpg.fraud_classification_type_id AND gfcpg.payment_method_group_id = paymentMethodGroupID;

  
  IF (clientIDCheck=-1 OR dissallowTransfer OR paymentGroupDepositAllowed = 0) THEN
      SET statusCode=8;
    END IF;

  END IF;
          
  
  SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
  
  IF (statusCode=0 AND playerRestrictionEnabled=1) THEN
    SET @numRestrictions=0;
    SET @restrictionType=NULL;
    SELECT restriction_types.name, COUNT(*) INTO @restrictionType, @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_transfers=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
    
    IF (@numRestrictions=1 AND @restrictionType='account_activation_policy' AND accountActivated=0) THEN
      SET statusCode = 10;
    ELSEIF (@numRestrictions > 0) THEN
      SET statusCode=9;
    END IF;
  END IF;

  IF (statusCode=0 AND isTestPlayer=0 AND performPaymentMethodChecks) THEN
    SET checkDepositLimitReturn = (SELECT TransactionCheckDepositAmountWithinLimit(clientStatID, paymentMethodID, varAmount, NULL)); 
        
    IF (checkDepositLimitReturn<>0) THEN
      CASE checkDepositLimitReturn
        WHEN 1 THEN SET statusCode=1;
        WHEN 2 THEN SET statusCode=4;
        WHEN 3 THEN SET statusCode=5;
        WHEN 4 THEN SET statusCode=6;
        ELSE SET statusCode=100; 
      END CASE;  
    END IF;
  END IF;
  
END$$

DELIMITER ;

