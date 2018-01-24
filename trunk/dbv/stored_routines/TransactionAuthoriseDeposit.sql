DROP procedure IF EXISTS `TransactionAuthoriseDeposit`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAuthoriseDeposit`(balanceAccountID BIGINT, accountReference VARCHAR(80), methodType VARCHAR(80), methodSubType VARCHAR(20), 
  clientID BIGINT, uniqueTransactionID VARCHAR(80), amountPriorCharges DECIMAL(18,5), varAmount DECIMAL(18, 5), currencyCode VARCHAR(80), paymentGatewayRef INT, ipAddress VARCHAR(40), OUT statusCode INT)
root:BEGIN

  
  

  DECLARE operatorID, balanceHistoryID, balanceAccountIDCheck, paymentMethodID, paymentSubMethodID, paymentMethodGroupID, currencyID, currencyIDCheck, paymentGatewayID, clientIDCheck, clientStatID BIGINT DEFAULT -1;
  DECLARE subPaymentMethodID BIGINT DEFAULT NULL;
  DECLARE beforeKYCDepositLimitEnabled, kycRequiredPerPlayerAccount, transactionAuthorized, fraudEnabled, fraudOnDepositEnabled, kycChecked, fraudCheckable TINYINT(1) DEFAULT 0; 
  DECLARE isSuspicious, depositAllowed, isTestPlayer, testPlayerAllowTransfers, playerDetailIsKycChecked, pendingRequest, playerRestrictionEnabled TINYINT(1) DEFAULT 0;
  DECLARE balanceAccountActive, balanceAccountActiveFlag TINYINT(1) DEFAULT 0;
  DECLARE depositedAmount, beforeKYCDepositLimit, exchangeRate DECIMAL(18, 5) DEFAULT 0;
  DECLARE checkDepositLimitReturn, transferDepositCaptureInterval, errorCode INT DEFAULT 0;
  DECLARE currencyCodeCheck, paymentGatewayName VARCHAR(80) DEFAULT NULL;
  DECLARE paymentGroupDepositAllowed, showPendingTransactions TINYINT(1) DEFAULT 1;
  
  SET statusCode=0;
  
  IF (clientID IS NULL) THEN
	SELECT client_id INTO clientID FROM gaming_balance_history WHERE unique_transaction_id=uniqueTransactionID; 
  END IF;

  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, is_suspicious, deposit_allowed, is_test_player, test_player_allow_transfers, gaming_clients.is_kyc_checked
  INTO clientIDCheck, clientStatID, isSuspicious, depositAllowed, isTestPlayer, testPlayerAllowTransfers, playerDetailIsKycChecked
  FROM gaming_client_stats  
  JOIN gaming_clients ON
    gaming_client_stats.client_id=clientID AND 
    gaming_clients.client_id=gaming_client_stats.client_id AND gaming_client_stats.is_active=1 
  FOR UPDATE;
  
  IF (clientStatID=-1 OR clientID=-1 OR clientID!=clientIDCheck) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;

  
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;
  
  
  SELECT balance_history_id, payment_method_id, ifnull(sub_payment_method_id, payment_method_id), client_stat_id, gaming_balance_history.currency_id, gaming_currency.currency_code, gaming_balance_history.pending_request  
  INTO balanceHistoryID, paymentMethodID, paymentSubMethodID, clientStatID, currencyID, currencyCodeCheck, pendingRequest
  FROM gaming_balance_history 
  JOIN gaming_currency ON gaming_balance_history.currency_id=gaming_currency.currency_id
  WHERE gaming_balance_history.unique_transaction_id=uniqueTransactionID; 
  
  
  SELECT payment_method_group_id INTO paymentMethodGroupID
  FROM gaming_payment_method
  WHERE payment_method_id=paymentSubMethodID;
  
  IF (balanceHistoryID=-1 OR pendingRequest=0) THEN
	SET statusCode=1;
    LEAVE root;
  END IF;
     
  IF (balanceHistoryID=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (UPPER(currencyCode)!=UPPER(currencyCodeCheck)) THEN
    SET statusCode=15;
    LEAVE root;
  END IF;
  
  SELECT currency_id, before_kyc_deposit_limit
  INTO currencyIDCheck, beforeKYCDepositLimit
  FROM gaming_payment_amounts
  WHERE currency_id=currencyID;
  
  IF (currencyIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  IF (statusCode=0 AND (isSuspicious=1 OR depositAllowed=0 OR (isTestPlayer=1 AND testPlayerAllowTransfers=0))) THEN
	SET statusCode=6;
  END IF;

  SELECT balance_account_id, kyc_checked, fraud_checkable, deposited_amount, is_active
  INTO balanceAccountIDCheck, kycChecked, fraudCheckable, depositedAmount, balanceAccountActive
  FROM gaming_balance_accounts 
  WHERE balance_account_id=balanceAccountID; 

   IF (statusCode=0 AND (balanceAccountIDCheck=-1 OR balanceAccountActive=0)) THEN
	 SET statusCode=17;
   END IF;
  
  
	IF (statusCode=0) THEN
	  
	  SET checkDepositLimitReturn = (SELECT TransactionCheckDepositAmountWithinLimit(clientStatID,IFNULL(subPaymentMethodID, paymentMethodID),varAmount,balanceAccountID)); 
	  	  
	  IF (checkDepositLimitReturn<>0 AND checkDepositLimitReturn<>2) THEN
		
		CASE checkDepositLimitReturn
		  WHEN 1 THEN SET statusCode=12;
		  WHEN 3 THEN SET statusCode=9;
		  WHEN 4 THEN SET statusCode=10; 
		  WHEN 13 THEN SET statusCode=20;
		  ELSE SET statusCode=100; 
		END CASE;    	   
	  END IF;
	END IF;
  
  IF (statusCode=0) THEN
	SET @isBannedIIN=0;
	
	SELECT 1 INTO @isBannedIIN
	FROM gaming_balance_accounts 
	JOIN gaming_payment_method ON
	  gaming_payment_method.name='CreditCard' AND
	  gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
	JOIN gaming_fraud_iins ON 
	  gaming_fraud_iins.is_active=1 AND 
	  SUBSTRING(gaming_balance_accounts.account_reference,1,6)=gaming_fraud_iins.iin_code AND gaming_fraud_iins.is_banned=1 
	WHERE gaming_balance_accounts.balance_account_id=balanceAccountID;
	
	IF (@isBannedIIN=1) THEN
	  SET statusCode=8;
	END IF;
  END IF;
  
  SELECT value_bool INTO fraudEnabled FROM gaming_settings WHERE name='FRAUD_ENABLED';
  SELECT value_bool INTO fraudOnDepositEnabled FROM gaming_settings WHERE name='FRAUD_ON_DEPOSIT_ENABLED';

  
  
  IF (fraudEnabled=1 AND fraudOnDepositEnabled=1 AND statusCode=0) THEN
    SET @fraudStatusCode=-1;
    SET @sessionID=0;
    
    CALL FraudEventRun(operatorID,clientID,'Deposit',balanceHistoryID,@sessionID,balanceAccountID,varAmount,0,@fraudStatusCode);
      
      IF (@fraudStatusCode<>0) THEN
        SET statusCode=11;
        LEAVE root;
      END IF;
            
      SET @clientIDCheck=-1;
      SET @dissallowTransfer=0;
	  SET paymentGroupDepositAllowed=1;
      SELECT client_id, disallow_transfers, IFNULL(deposit_allowed,1) INTO @clientIDCheck, @dissallowTransfer, paymentGroupDepositAllowed
      FROM gaming_fraud_client_events AS cl_events
      JOIN gaming_fraud_classification_types ON 
        cl_events.client_id=clientID AND cl_events.is_current=1 AND
        cl_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id
	  LEFT JOIN gaming_fraud_classification_payment_groups gfcpg ON 
		gaming_fraud_classification_types.fraud_classification_type_id = gfcpg.fraud_classification_type_id AND gfcpg.payment_method_group_id = paymentMethodGroupID;
      
      
      IF (@clientIDCheck=-1) THEN
        SET statusCode=11;
        LEAVE root;
      END IF;
      
      IF (@dissallowTransfer=1 OR paymentGroupDepositAllowed = 0) THEN
        SET statusCode=7;
      END IF;
  END IF;

  SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
  IF (statusCode=0 AND playerRestrictionEnabled=1) THEN
	SET @numRestrictions=0;
    SELECT COUNT(*) INTO @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_transfers=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
  
    IF (@numRestrictions > 0) THEN
      SET statusCode=18;
	END IF;
  END IF;

  IF (statusCode!=0) THEN
    SET errorCode =     
      CASE 
        WHEN statusCode=6 THEN 3 
        WHEN statusCode=7 THEN 4 
        WHEN statusCode=8 THEN 5 
        WHEN statusCode=9 THEN 6 
        WHEN statusCode=10 THEN 7 
        WHEN statusCode=11 THEN 8 
        WHEN statusCode=12 THEN 9 
        WHEN statusCode=13 THEN 1 
        WHEN statusCode=16 THEN 16 
        WHEN statusCode=17 THEN 21 
		WHEN statusCode=18 THEN 11 
        ELSE 10 
      END;
  ELSE
	SET errorCode=0;
  END IF;

  SELECT gaming_operator_currency.exchange_rate INTO exchangeRate
  FROM gaming_client_stats 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  WHERE gaming_client_stats.client_stat_id=clientStatID;

  SELECT value_bool INTO showPendingTransactions FROM gaming_settings WHERE `name`='TRANSACTION_SHOW_PENDING_TRANSACTIONS';

  UPDATE gaming_balance_history
  JOIN gaming_payment_transaction_status ON LOWER(gaming_payment_transaction_status.name)=LOWER(IF(statusCode=0,'Pending','Rejected'))
  JOIN gaming_balance_accounts ON gaming_balance_accounts.balance_account_id=balanceAccountID  
  LEFT JOIN gaming_balance_history_error_codes ON gaming_balance_history_error_codes.error_code=errorCode
  SET 
	gaming_balance_history.timestamp=NOW(),
	gaming_balance_history.pending_request=IF(statusCode=0, 1, 0),
    gaming_balance_history.is_processed=IF(statusCode=0, 0, 1),
    gaming_balance_history.amount_prior_charges=IFNULL(amountPriorCharges , gaming_balance_history.amount_prior_charges),
    gaming_balance_history.amount_prior_charges_base=IFNULL(ROUND(amountPriorCharges/exchangeRate,5), gaming_balance_history.amount_prior_charges_base),
	gaming_balance_history.amount = IF(pendingRequest=1, varAmount, gaming_balance_history.amount),
    gaming_balance_history.amount_base = IF(pendingRequest=1, ROUND(varAmount/exchangeRate,5), gaming_balance_history.amount_base),
	gaming_balance_history.payment_transaction_status_id = IF(showPendingTransactions=0 AND statusCode=0, NULL, gaming_payment_transaction_status.payment_transaction_status_id), 
    gaming_balance_history.payment_method_id = gaming_balance_accounts.payment_method_id,
	gaming_balance_history.sub_payment_method_id = gaming_balance_accounts.sub_payment_method_id,
    gaming_balance_history.balance_account_id = gaming_balance_accounts.balance_account_id,
    gaming_balance_history.account_reference = IFNULL(gaming_balance_history.account_reference, IFNULL(accountReference, gaming_balance_accounts.account_reference)), 
    gaming_balance_history.balance_history_error_code_id=IFNULL(gaming_balance_history_error_codes.balance_history_error_code_id,1),
    gaming_balance_history.description = gaming_balance_history_error_codes.message, 
    gaming_balance_history.ip_address= IFNULL(ipAddress, gaming_balance_history.ip_address)
  WHERE gaming_balance_history.balance_history_id=balanceHistoryID;

END root$$

DELIMITER ;

