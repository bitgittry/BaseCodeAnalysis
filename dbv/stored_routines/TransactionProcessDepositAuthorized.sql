DROP procedure IF EXISTS `TransactionProcessDepositAuthorized`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionProcessDepositAuthorized`(isCaptureIntervalEnabled TINYINT(1), orderRef BIGINT, transactionStatus VARCHAR(80), canReject TINYINT(1), varTimestamp DATETIME, accountReference VARCHAR(80), methodSubType VARCHAR(20), 
  clientID BIGINT, uniqueTransactionID VARCHAR(80), varAmount DECIMAL(18, 5), currencyCode VARCHAR(80), paymentGatewayRef INT, paymentGatewayTransactionKey VARCHAR(255), cardHolderName VARCHAR(255), expiryDate DATE, playerToken VARCHAR(100), customMessage VARCHAR(1024), balanceManualTransactionID BIGINT, bonusCode VARCHAR(80), OUT statusCode INT)
root:BEGIN
  
  -- Balance Account ID from manaul transaction if there is and not not null 
 
  DECLARE operatorID, balanceHistoryID, balanceAccountID, paymentMethodID, paymentMethodGroupID, currencyID, currencyIDCheck, paymentGatewayID, clientIDCheck, clientStatID, clientStatIDCheck, paymentTransactionStatusID BIGINT DEFAULT -1;
  DECLARE subPaymentMethodID, bonusInstanceID BIGINT DEFAULT NULL;
  DECLARE beforeKYCDepositLimitEnabled, kycRequiredPerPlayerAccount, clientStatBalanceUpdated, clientStatBalanceRefunded, transactionAuthorized, fraudEnabled, fraudOnDepositEnabled, kycChecked, fraudCheckable, notificationEnabled ,ruleEngineEnabled TINYINT(1) DEFAULT 0; 
  DECLARE isSuspicious, depositAllowed, isTestPlayer, testPlayerAllowTransfers, playerDetailIsKycChecked, updateClientStatFunds, refundClientStatFunds, isRejected, isAccepted, isProcessed, pendingRequest, playerRestrictionEnabled TINYINT(1) DEFAULT 0;
  DECLARE balanceAccountActive, transferDepositCaptureIntervalEnabled, invalidateDefaultAccount, balanceAccountActiveFlag, canWithdraw, isInternal, isInstantPayment, isManualTransaction, saveUniqueTransactionIDLast, disableSaveAccountBalance TINYINT(1) DEFAULT 0;
  DECLARE depositedAmount, beforeKYCDepositLimit, exchangeRate, currentRealBalance, maxPlayerBalanceThreshold, chargeAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE checkDepositLimitReturn, transferDepositCaptureInterval, errorCode, numDeposits INT DEFAULT 0;
  DECLARE processAtDatetime, firstDepositDate DATETIME DEFAULT NULL;
  DECLARE currencyCodeCheck, paymentGatewayName, uniqueTransactionIDLast VARCHAR(80) DEFAULT NULL;
  DECLARE platformTypeID TINYINT(4) DEFAULT NULL;  
  DECLARE bonusRedeemAll,noMoreRecords BIT DEFAULT 0;
  DECLARE retryPlayerSubscription, WagerBeforeWithdrawal TINYINT(1) DEFAULT 1;
  DECLARE paymentMethodIntegrationTypeString VARCHAR(80) DEFAULT NULL;
  DECLARE v_is_default_withdrawal, maxBalanceThresholdEnabled, canDeposit TINYINT(1) DEFAULT 0;
  DECLARE crnCheckSum integer DEFAULT 0;
  

  DECLARE redeemCursor CURSOR FOR 
    SELECT 	gbi.bonus_instance_id 
	FROM 	gaming_client_stats AS gcs
			JOIN gaming_bonus_instances AS gbi 
				ON gbi.client_stat_id=gcs.client_stat_id 
				AND gbi.open_rounds < 1
				AND gbi.is_active = 1
				AND gcs.client_id = clientID
			JOIN gaming_bonus_rules gbr 
				ON gbi.bonus_rule_id = gbr.bonus_rule_id				
				AND gbr.redeem_threshold_enabled = 1 
				AND gbr.redeem_threshold_on_deposit = 1
			JOIN gaming_bonus_rules_wager_restrictions AS restrictions 
				ON restrictions.bonus_rule_id=gbi.bonus_rule_id 
				AND restrictions.currency_id=gcs.currency_id 			
	WHERE restrictions.redeem_threshold >= gbi.bonus_amount_remaining+current_win_locked_amount;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SET statusCode=0;
  SET canReject=canReject AND transactionStatus='Authorized_Pending';

  SELECT value_bool INTO maxBalanceThresholdEnabled FROM gaming_settings WHERE name='MAXIMUM_PLAYER_EWALLET_BALANCE_THRESHOLD_ENABLED' ;
 

  IF (clientID IS NULL) THEN
	SELECT client_id INTO clientID FROM gaming_balance_history WHERE unique_transaction_id=uniqueTransactionID; 
  END IF;

  SELECT gs1.value_bool as vb1
  INTO ruleEngineEnabled
  FROM gaming_settings gs1 
  WHERE gs1.name='RULE_ENGINE_ENABLED';
	
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats FORCE INDEX (client_id) WHERE client_id=clientID AND is_active FOR UPDATE;

  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, is_suspicious, deposit_allowed, is_test_player, test_player_allow_transfers, gaming_clients.is_kyc_checked, gaming_clients.first_deposit_date, gaming_client_stats.current_real_balance, ifnull(gaming_client_stats.max_player_balance_threshold,gaming_countries.max_player_balance_threshold) as max_player_balance_threshold
  INTO clientIDCheck, clientStatIDCheck, isSuspicious, depositAllowed, isTestPlayer, testPlayerAllowTransfers, playerDetailIsKycChecked, firstDepositDate, currentRealBalance, maxPlayerBalanceThreshold
  FROM gaming_client_stats  FORCE INDEX (client_id)    
  STRAIGHT_JOIN gaming_clients ON
    gaming_client_stats.client_id=clientID AND gaming_client_stats.is_active=1 AND 
    gaming_clients.client_id=gaming_client_stats.client_id
  LEFT JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id AND clients_locations.is_primary = 1
  LEFT JOIN gaming_countries ON clients_locations.country_id = gaming_countries.country_id;
  
  IF (clientStatIDCheck=-1 OR clientID=-1 OR clientID!=clientIDCheck) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;
  
   
  SELECT balance_history_id, client_stat_id, client_stat_balance_updated, client_stat_balance_refunded, payment_method_id, gaming_balance_history.currency_id, gaming_currency.currency_code, gaming_balance_history.pending_request, gaming_balance_history.is_processed, 
    sub_payment_method_id, payment_gateway_id, gaming_balance_history.platform_type_id, gaming_balance_history.payment_transaction_status_id,retry_player_subscriptions, charge_amount
  INTO balanceHistoryID, clientStatID, clientStatBalanceUpdated, clientStatBalanceRefunded, paymentMethodID, currencyID, currencyCodeCheck, pendingRequest, isProcessed, 
    subPaymentMethodID, paymentGatewayID, platformTypeID, paymentTransactionStatusID,retryPlayerSubscription, chargeAmount
  FROM gaming_balance_history 
  JOIN gaming_currency ON gaming_balance_history.currency_id=gaming_currency.currency_id
  WHERE gaming_balance_history.unique_transaction_id=uniqueTransactionID; 
  
  IF (isProcessed=1) THEN
	
	IF (NOT (clientStatBalanceUpdated=0 AND transactionStatus IN ('Accepted','Authorized_Pending') AND IFNULL(paymentTransactionStatusID,0) IN (3,4,5,8))) THEN
	  
	  IF (NOT (clientStatBalanceUpdated=1 AND clientStatBalanceRefunded=0 AND transactionStatus NOT IN ('Accepted','Authorized_Pending','Authorized_Complete'))) THEN
		
		IF (NOT (clientStatBalanceUpdated=1 AND clientStatBalanceRefunded=1 AND transactionStatus='Accepted' AND paymentTransactionStatusID=5)) THEN
			LEAVE root;
		END IF;
	  END IF;
	END IF;
  END IF;
     
  IF (balanceHistoryID=-1 OR clientStatID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (UPPER(currencyCode)!=UPPER(currencyCodeCheck)) THEN
    SET statusCode=15;
    LEAVE root;
  END IF;
  
  IF (methodSubType IS NOT NULL) THEN
    SELECT payment_method_id INTO subPaymentMethodID 
    FROM gaming_payment_method 
    WHERE parent_payment_method_id=paymentMethodID AND payment_gateway_method_sub_name=methodSubType;
  END IF;
  
  SET subPaymentMethodID=IFNULL(subPaymentMethodID,paymentMethodID);
  
  SELECT gpm.invalidate_default_account, gpm.is_instant_payment, gpm.can_deposit, pmit.name, gpm.wager_before_withdrawal
  INTO invalidateDefaultAccount, isInstantPayment, canDeposit, paymentMethodIntegrationTypeString, WagerBeforeWithdrawal
  FROM gaming_payment_method gpm
  LEFT JOIN gaming_payment_method_integration_types pmit USING(payment_method_integration_type_id)
  WHERE payment_method_id=paymentMethodID;
  
  IF(canDeposit = 0) THEN
	SET statusCode=20;
  END IF;
  
  SELECT payment_method_group_id INTO paymentMethodGroupID
  FROM gaming_payment_method
  WHERE payment_method_id=subPaymentMethodID;
     
  SELECT currency_id, before_kyc_deposit_limit
  INTO currencyIDCheck, beforeKYCDepositLimit
  FROM gaming_payment_amounts
  WHERE currency_id=currencyID;
  
  IF (currencyIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SELECT payment_gateway_id, name, disable_save_account_balance INTO paymentGatewayID, paymentGatewayName, disableSaveAccountBalance 
  FROM gaming_payment_gateways 
  WHERE payment_gateway_ref=paymentGatewayRef;
  
  IF (paymentGatewayID=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;  
  
  SET transactionStatus=UPPER(transactionStatus);
  IF (transactionStatus='VOID') THEN
    SET transactionStatus='Rejected';
    SET statusCode=13;
  END IF;
  
  SET @payment_transaction_status_id=-1;
  SET @transactionStatus = NULL;  
  SELECT payment_transaction_status_id, name INTO @payment_transaction_status_id, @transactionStatus
  FROM gaming_payment_transaction_status
  WHERE UPPER(name)=transactionStatus;
  
  if (@payment_transaction_status_id=-1) THEN
    SET statusCode=4;
    LEAVE root;
  ELSE
    SET transactionStatus=@transactionStatus;
  END IF;
  
  
  IF (statusCode=0) THEN
    IF (transactionStatus IN ('Authorized_Complete','Accepted')) THEN
      SET transactionStatus = 'Accepted';
      SET isAccepted=1;
    ELSEIF (transactionStatus IN ('Not_Set','Declined','Authorized_Rejected','Authorized_Voided')) THEN
      SET transactionStatus = 'Rejected';  
    ELSEIF (isInstantPayment=1 AND transactionStatus IN ('Blocked')) THEN 
      SET transactionStatus = 'Rejected';
    ELSEIF (transactionStatus='Cancelled') THEN
      SET transactionStatus='Rejected';
      SET statusCode=16;
    END IF;
  END IF;
  
  IF (pendingRequest=1 AND isAccepted=0 AND canReject) THEN 
    IF (statusCode=0 AND (isSuspicious=1 OR depositAllowed=0 OR (isTestPlayer=1 AND testPlayerAllowTransfers=0))) THEN
      SET isAccepted=0;
      SET statusCode=6;
      SET transactionStatus='Rejected';
    END IF;
  END IF;
  
  
  IF(accountReference IS NOT NULL) THEN
	SET accountReference=IF(TRIM(accountReference)='', NULL, accountReference);
  END IF;

  IF (accountReference IS NULL AND transactionStatus='Rejected') THEN
	SET invalidateDefaultAccount=1;
	SET accountReference='InvalidAccount';
	SET isInternal=1;
	SET balanceAccountActiveFlag=0;
  ELSE
	SET accountReference=IFNULL(accountReference, 'Account');
	SET isInternal=IF(accountReference='InvalidAccount', 1, 0);
	SET balanceAccountActiveFlag=1;
  END IF;

  SELECT IF(invalidateDefaultAccount, 'InvalidAccount', 'Account') INTO accountReference
  FROM gaming_payment_gateways_acc_ref_replacements
  WHERE payment_gateway_id=paymentGatewayID AND UPPER(match_string)=UPPER(accountReference);
  
  IF (balanceManualTransactionID IS NOT NULL) THEN
  
	SELECT IFNULL(balance_account_id, -1) INTO balanceAccountID FROM gaming_balance_manual_transactions WHERE balance_manual_transaction_id=balanceManualTransactionID;
   
	IF (balanceAccountID != -1) THEN
		SELECT balance_account_id, kyc_checked, fraud_checkable, deposited_amount, is_active, unique_transaction_id_last
		INTO balanceAccountID, kycChecked, fraudCheckable, depositedAmount, balanceAccountActive, uniqueTransactionIDLast
		FROM gaming_balance_accounts 
		WHERE balance_account_id=balanceAccountID;
    END IF;
  
  END IF;
	
  IF (balanceAccountID = -1) THEN	
	SELECT balance_account_id, kyc_checked, fraud_checkable, deposited_amount, is_active, unique_transaction_id_last
    INTO balanceAccountID, kycChecked, fraudCheckable, depositedAmount, balanceAccountActive, uniqueTransactionIDLast
    FROM gaming_balance_accounts 
    WHERE account_reference=accountReference AND client_stat_id=clientStatID AND payment_method_id=paymentMethodID AND (payment_gateway_id IS NULL OR payment_gateway_id=paymentGatewayID) AND is_active = 1
	ORDER BY date_created DESC
    LIMIT 1;
  END IF;
   
  SELECT value_bool INTO beforeKYCDepositLimitEnabled FROM gaming_settings WHERE name='TRANSFER_BEFORE_KYC_DEPOSIT_LIMIT_ENABLED';
  SELECT value_bool INTO kycRequiredPerPlayerAccount FROM gaming_settings WHERE name='TRANSFER_KYC_REQUIRED_PER_PLAYER_ACCOUNT';
  SELECT value_bool INTO bonusRedeemAll FROM gaming_settings WHERE `name` = 'BONUS_REEDEM_ALL_BONUS_ON_REDEEM';

  SET @sessionID=0;
  SET canWithdraw=IF(isAccepted=1 AND uniqueTransactionID IS NOT NULL, 1, 0);
  SET isManualTransaction=IF(balanceManualTransactionID IS NULL, 0, 1);
  SET saveUniqueTransactionIDLast=IF(isAccepted=1 AND isManualTransaction=0 AND uniqueTransactionID IS NOT NULL AND disableSaveAccountBalance=0, 1, 0);
  SET uniqueTransactionIDLast=IF(saveUniqueTransactionIDLast, uniqueTransactionID, uniqueTransactionIDLast);
  SET playerToken=IF(paymentGatewayName='Wirecard' AND saveUniqueTransactionIDLast=0, NULL, playerToken);

  IF (balanceAccountID=-1) THEN
  
    SET @numAccounts=0;
    SELECT COUNT(*) INTO @numAccounts
    FROM gaming_balance_accounts
    WHERE client_stat_id=clientStatID AND payment_method_id=paymentMethodID;
    SET @isDefault=IF(@numAccounts=0, 1, 0);
    
    SET @balance_account_size = 0;
    SELECT COUNT(*) INTO @balance_account_size FROM gaming_balance_accounts WHERE client_stat_id = clientStatID;
    SET v_is_default_withdrawal = IF (@balance_account_size = 0, 1, 0);
    
    INSERT INTO gaming_balance_accounts (account_reference, date_created, date_last_used, kyc_checked, client_stat_id, is_active, unique_transaction_id_last, payment_method_id, sub_payment_method_id, deposited_amount, cc_holder_name, session_id, can_withdraw, is_internal, is_default, payment_gateway_id, expiry_date, player_token, is_default_withdrawal)
    SELECT accountReference, NOW(), NOW(), 0, clientStatID, balanceAccountActiveFlag, IF(saveUniqueTransactionIDLast,uniqueTransactionID,NULL), paymentMethodID, subPaymentMethodID, 0, cardHolderName, @sessionID, IF(gaming_payment_method.can_withdraw AND canWithdraw, 1, 0), isInternal, @isDefault, paymentGatewayID, expiryDate, playerToken, v_is_default_withdrawal
    FROM gaming_payment_method
    WHERE payment_method_id=paymentMethodID;

	SET balanceAccountID = LAST_INSERT_ID();
	SET balanceAccountActive=1;
    
    -- SUP-6440 we have to update balanceAccountID in order to be able later to link gaming_balance_history with gaming_balance_accounts
    UPDATE gaming_balance_history
    SET balance_account_id = balanceAccountID,
	    payment_gateway_transaction_key = paymentGatewayTransactionKey
    WHERE unique_transaction_id = uniqueTransactionID;  
    
    UPDATE gaming_balance_history gbh
    JOIN gaming_balance_accounts ba ON gbh.balance_account_id = ba.balance_account_id
    SET  gbh.account_reference = ba.account_reference,
	     gbh.payment_method_id = ba.payment_method_id,
         gbh.sub_payment_method_id = ba.sub_payment_method_id
    WHERE gbh.unique_transaction_id = uniqueTransactionID;
    

	IF (paymentMethodIntegrationTypeString = 'manual') THEN
		SET crnCheckSum = GenerateLuhn(balanceAccountID);
		INSERT INTO gaming_balance_account_attributes(balance_account_id, attr_name, attr_value) VALUES (balanceAccountID, 'crn', CONCAT(balanceAccountID, crnCheckSum));
	END IF;
    
  ELSE
    IF (isAccepted) THEN
      
      
      UPDATE gaming_balance_accounts 
      JOIN gaming_payment_method ON gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
      SET gaming_balance_accounts.date_last_used=NOW(), gaming_balance_accounts.is_active=(balanceAccountActiveFlag AND gaming_balance_accounts.is_active), gaming_balance_accounts.unique_transaction_id_last=IF(saveUniqueTransactionIDLast,uniqueTransactionID,unique_transaction_id_last), 
		  gaming_balance_accounts.cc_holder_name=IFNULL(cardHolderName,gaming_balance_accounts.cc_holder_name), gaming_balance_accounts.expiry_date=IFNULL(expiryDate,gaming_balance_accounts.expiry_date),  gaming_balance_accounts.player_token=IFNULL(playerToken,gaming_balance_accounts.player_token),  
          gaming_balance_accounts.can_withdraw=IF(gaming_payment_method.can_withdraw AND canWithdraw  AND gaming_balance_accounts.is_internal = 0, 1, 0), gaming_balance_accounts.session_id=@sessionID 
      WHERE gaming_balance_accounts.balance_account_id=balanceAccountID;
    END IF;
  END IF;
  
  IF (balanceAccountID=-1) THEN
    SET statusCode=14;
    LEAVE root;
  END IF;
  
  IF (paymentGatewayName='External' AND disableSaveAccountBalance=1 AND saveUniqueTransactionIDLast=0 AND uniqueTransactionIDLast IS NULL AND accountReference<>'Account') THEN
    CALL PaymentCreateDummyPurchaseForWithdrawal(balanceAccountID, paymentGatewayTransactionKey, @dps);
  END IF;
  
  
  IF (transactionStatus='Authorized_Pending' AND statusCode=0 AND canReject) THEN
    IF (balanceAccountActive=0) THEN
      SET statusCode=17;
      SET transactionStatus='Rejected';
    END IF;
  END IF;
  
  IF(statusCode=0 AND canReject AND maxBalanceThresholdEnabled = 1 AND NOT ISNULL(maxPlayerBalanceThreshold) AND 
		(maxPlayerBalanceThreshold = 0 OR (currentRealBalance + varAmount > maxPlayerBalanceThreshold))) THEN
        
	SET statusCode=19;
    SET transactionStatus='Rejected';
  END IF;  
  IF (statusCode=0 AND pendingRequest=1 AND isAccepted=0 AND canReject) THEN
  
    IF (canReject AND statusCode=0) THEN
      
      SET checkDepositLimitReturn = (SELECT TransactionCheckDepositAmountWithinLimit(clientStatID,IFNULL(subPaymentMethodID, paymentMethodID),varAmount,balanceAccountID)); 
      
      
      IF (checkDepositLimitReturn<>0 AND checkDepositLimitReturn<>2) THEN
        
        CASE checkDepositLimitReturn
          WHEN 1 THEN SET statusCode=12;
          WHEN 3 THEN SET statusCode=9;
          WHEN 4 THEN SET statusCode=10; 
          ELSE SET statusCode=100; 
        END CASE;    
       
        SET transactionStatus='Rejected';
      END IF;
    END IF;
    
    IF (statusCode=0 AND canReject) THEN
      
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
          SET transactionStatus='Rejected';
        END IF;
      END IF;
          
    END IF;
  END IF;
  
  SELECT value_bool INTO fraudEnabled FROM gaming_settings WHERE name='FRAUD_ENABLED';
  SELECT value_bool INTO fraudOnDepositEnabled FROM gaming_settings WHERE name='FRAUD_ON_DEPOSIT_ENABLED';
  
  IF ((fraudEnabled=1 AND fraudOnDepositEnabled=1) AND pendingRequest=1) THEN
    SET @fraudStatusCode=-1;
    SET @sessionID=0;
    
    CALL FraudEventRun(operatorID,clientID,'Deposit',balanceHistoryID,@sessionID,balanceAccountID,varAmount,0,@fraudStatusCode);
    
    IF (canReject AND statusCode=0 AND pendingRequest=1) THEN
      
      IF (@fraudStatusCode<>0) THEN
        SET statusCode=11;
        LEAVE root;
      END IF;
            
      SET @clientIDCheck=-1;
      SET @dissallowTransfer=0;
	  SET @paymentGroupDepositAllowed=1;
      SELECT client_id, disallow_transfers, IFNULL(deposit_allowed,1) INTO @clientIDCheck, @dissallowTransfer, @paymentGroupDepositAllowed
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
      
      IF ((@dissallowTransfer=1 OR @paymentGroupDepositAllowed = 0) AND canReject) THEN
		SET statusCode=7;
        SET transactionStatus='Rejected';
      END IF;
    END IF;
  END IF;

  SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
  IF (statusCode=0 AND playerRestrictionEnabled=1 AND canReject) THEN
	SET @numRestrictions=0;
    SELECT COUNT(*) INTO @numRestrictions
    FROM gaming_player_restrictions
    JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_transfers=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
    WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
  
    IF (@numRestrictions > 0) THEN
      SET statusCode=18;
	  SET transactionStatus='Rejected';
	END IF;
  END IF;
  
  
  SELECT gaming_operator_currency.exchange_rate INTO exchangeRate
  FROM gaming_client_stats 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET @timestamp=NOW();
  SET updateClientStatFunds=statusCode=0 AND clientStatBalanceUpdated=0 AND (transactionStatus='Accepted' OR (isCaptureIntervalEnabled=1 AND transactionStatus='Authorized_Pending'));
  SET refundClientStatFunds=statusCode=0 AND isCaptureIntervalEnabled=1 AND clientStatBalanceUpdated=1 AND clientStatBalanceRefunded=0 AND transactionStatus='Rejected';
  
  SET @enableUpdateAffiliateAdjustment=1;
  
  
  IF (clientStatBalanceUpdated=1 AND clientStatBalanceRefunded=1 AND paymentTransactionStatusID=5 AND transactionStatus='Accepted') THEN

	UPDATE gaming_client_stats 
	SET current_real_balance=current_real_balance+varAmount, deposited_amount=deposited_amount+varAmount, deposited_amount_base=deposited_amount_base+ROUND(varAmount/exchangeRate, 5), last_deposited_date=NOW(), first_deposited_date=IFNULL(first_deposited_date, NOW()), num_deposits=num_deposits+1,
    locked_real_funds = IF(WagerBeforeWithdrawal,locked_real_funds + varAmount,locked_real_funds),
	deposited_charge_amount=deposited_charge_amount+chargeAmount, deposited_charge_amount_base=deposited_charge_amount_base+ROUND(chargeAmount/exchangeRate,5)
	WHERE gaming_client_stats.client_stat_id=clientStatID;

	UPDATE gaming_clients SET first_deposit_date=IFNULL(@timestamp,first_deposit_date), first_deposit_balance_history_id=IFNULL(balanceHistoryID, first_deposit_balance_history_id) WHERE client_id=clientID AND first_deposit_date IS NULL;
    
    UPDATE gaming_balance_accounts 
    SET deposited_amount=deposited_amount+varAmount, date_last_used=NOW(), deposited_charge_amount=deposited_charge_amount+chargeAmount, deposited_charge_amount_base=deposited_charge_amount_base+ROUND(chargeAmount/exchangeRate,5)
    WHERE balance_account_id=balanceAccountID;
  
      -- SUP-6440		
    UPDATE gaming_balance_history		
    SET balance_account_id = IFNULL(balanceAccountID, balance_account_id),		
		payment_gateway_transaction_key = IFNULL(paymentGatewayTransactionKey, payment_gateway_transaction_key)		
    WHERE unique_transaction_id = uniqueTransactionID;
	  
	INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, reason, extra_id, balance_history_id, pending_bet_real, pending_bet_bonus, platform_type_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount, ROUND(varAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, varAmount, 0, 0, 0, @timestamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance,current_loyalty_points, customMessage, paymentMethodID, balanceHistoryID, pending_bets_real, pending_bets_bonus, platformTypeID , withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
	FROM gaming_client_stats 
	JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
	JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
	WHERE gaming_client_stats.client_stat_id=clientStatID;  

	SET @transactionID=LAST_INSERT_ID();
    
	INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
	SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
	FROM gaming_transactions
	WHERE transaction_id=@transactionID;

	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());

	SET updateClientStatFunds=1;
    
  ELSEIF (updateClientStatFunds) THEN
    

    IF (@enableUpdateAffiliateAdjustment) THEN
      CALL TransactionProcessDepositAffiliateAdjustment(clientStatID, balanceHistoryID, varAmount, 0);
    END IF;
    
    
    UPDATE gaming_client_stats 
    SET current_real_balance=current_real_balance+varAmount, deposited_amount=deposited_amount+varAmount,
		deposited_amount_base=deposited_amount_base+ROUND(varAmount/exchangeRate, 5), last_deposited_date=NOW(), first_deposited_date=IFNULL(first_deposited_date, NOW()), num_deposits=num_deposits+1,
		locked_real_funds = IF(WagerBeforeWithdrawal,locked_real_funds + varAmount,locked_real_funds), deposited_charge_amount=deposited_charge_amount+chargeAmount, deposited_charge_amount_base=deposited_charge_amount_base+ROUND(chargeAmount/exchangeRate,5)
    WHERE gaming_client_stats.client_stat_id=clientStatID;
    
    UPDATE gaming_clients SET first_deposit_date=IFNULL(@timestamp,first_deposit_date), first_deposit_balance_history_id=IFNULL(balanceHistoryID, first_deposit_balance_history_id) WHERE client_id=clientID AND first_deposit_date IS NULL;
    
    IF (firstDepositDate IS NULL AND (fraudEnabled=1 AND fraudOnDepositEnabled=1)) THEN
      SET @fraudStatusCode=-1;
      SET @sessionID=0;
      CALL FraudEventRun(operatorID,clientID,'Deposit',balanceHistoryID,@sessionID,NULL,varAmount,0,@fraudStatusCode);
    END IF;
    
    
    UPDATE gaming_balance_accounts 
    SET deposited_amount=deposited_amount+varAmount, date_last_used=NOW(),deposited_charge_amount=deposited_charge_amount+chargeAmount, deposited_charge_amount_base=deposited_charge_amount_base+ROUND(chargeAmount/exchangeRate,5)
    WHERE balance_account_id=balanceAccountID;
    
	
	SET @DISABLE_PAYMENT_METHOD_ON_GATEWAY_CHANGE = (SELECT value_bool from gaming_settings WHERE `name` = 'DISABLE_PAYMENT_METHOD_ON_GATEWAY_CHANGE');

	IF (@DISABLE_PAYMENT_METHOD_ON_GATEWAY_CHANGE = 1) THEN
		UPDATE gaming_balance_accounts 
		SET is_active= 0		
		WHERE account_reference = accountReference		  
			AND balance_account_id != balanceAccountID
			AND client_stat_id = clientStatID;
	END IF;    

	
    INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, reason, extra_id, balance_history_id, pending_bet_real, pending_bet_bonus, platform_type_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount, ROUND(varAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, varAmount, 0, 0, 0, @timestamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance,current_loyalty_points, customMessage, paymentMethodID, balanceHistoryID, pending_bets_real, pending_bets_bonus, platformTypeID , withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
    FROM gaming_client_stats 
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='Deposit'
    WHERE gaming_client_stats.client_stat_id=clientStatID;  

    SET @transactionID=LAST_INSERT_ID();
  
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
    FROM gaming_transactions
    WHERE transaction_id=@transactionID;

	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());
  
  ELSEIF (refundClientStatFunds) THEN
    IF (@enableUpdateAffiliateAdjustment) THEN
      CALL TransactionProcessDepositAffiliateAdjustment(clientStatID, balanceHistoryID, varAmount, 1);
    END IF;
    
    
    UPDATE gaming_client_stats 
    SET current_real_balance=current_real_balance-varAmount, deposited_amount=deposited_amount-varAmount, deposited_amount_base=deposited_amount_base-ROUND(varAmount/exchangeRate, 5), num_deposits=num_deposits-1,
		locked_real_funds = IF(WagerBeforeWithdrawal,GREATEST(locked_real_funds - varAmount,0), locked_real_funds), deposited_charge_amount=deposited_charge_amount-chargeAmount, deposited_charge_amount_base=deposited_charge_amount_base-ROUND(chargeAmount/exchangeRate,5)
    WHERE gaming_client_stats.client_stat_id=clientStatID;
    
    
    UPDATE gaming_balance_accounts 
    SET deposited_amount=deposited_amount-varAmount, deposited_charge_amount=deposited_charge_amount-chargeAmount, deposited_charge_amount_base=deposited_charge_amount_base-ROUND(chargeAmount/exchangeRate,5)
    WHERE balance_account_id=balanceAccountID;
    
    
    INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, reason, extra_id, balance_history_id, pending_bet_real, pending_bet_bonus, platform_type_id,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount*-1, ROUND(varAmount/exchangeRate,5)*-1, gaming_client_stats.currency_id, exchangeRate, varAmount*-1, 0, 0, 0, @timestamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, customMessage, paymentMethodID, balanceHistoryID , pending_bets_real, pending_bets_bonus, platformTypeID ,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
    FROM gaming_client_stats 
    JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
    JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='DepositCancelled'
    WHERE gaming_client_stats.client_stat_id=clientStatID;  
    
    SET @transactionID=LAST_INSERT_ID();
  
    INSERT INTO gaming_game_plays 
    (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
    SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, platform_type_id,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus
    FROM gaming_transactions
    WHERE transaction_id=@transactionID;
	
	CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());

  END IF;
  
  IF (ruleEngineEnabled) AND lower(transactionStatus) IN ('accepted') THEN
      IF NOT EXISTS (SELECT event_table_id FROM gaming_event_rows WHERE event_table_id=2 AND elem_id=balanceHistoryID) THEN
		    INSERT INTO gaming_event_rows (event_table_id, elem_id) SELECT 2, balanceHistoryID
          ON DUPLICATE KEY UPDATE elem_id=VALUES(elem_id);
      END IF;
  END IF;
    
  
  SELECT value_bool INTO transferDepositCaptureIntervalEnabled FROM gaming_settings WHERE name='TRANSFER_DEPOSIT_CAPTURE_INTERVAL_ENABLED';
  SELECT value_int INTO transferDepositCaptureInterval FROM gaming_settings WHERE name='TRANSFER_DEPOSIT_CAPTURE_INTERVAL';
    
  SET isRejected=statusCode!=0 OR (statusCode=0 AND NOT (transactionStatus='Authorized_Pending' OR transactionStatus='Accepted' OR transactionStatus='Pending'));
  
  SET processAtDatetime=NULL;
  IF (isProcessed=0) THEN 
  
    IF(isRejected OR isAccepted) THEN
      SET isProcessed=1;
    ELSEIF (transferDepositCaptureIntervalEnabled AND pendingRequest) THEN
      SET processAtDatetime = DATE_ADD(NOW(), INTERVAL transferDepositCaptureInterval MINUTE);
      SET isProcessed = 0;
    END IF;  
 
  END IF;
  
  IF (isRejected) THEN
    SET errorCode =     
      CASE 
        WHEN refundClientStatFunds=1 THEN 1 
        WHEN statusCode=0 AND (transactionStatus IN ('Authorized_Pending','Accepted')) THEN 0 
        WHEN statusCode=0 AND NOT (transactionStatus IN ('Authorized_Pending','Accepted')) THEN 2 
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
		WHEN statusCode=19 THEN 25
	    ELSE 10 
      END;
  ELSE
    SET isRejected=0;
  END IF;
    
  SELECT num_deposits INTO numDeposits FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  
	IF ((balanceManualTransactionID IS NULL OR balanceManualTransactionID = 0) AND paymentMethodIntegrationTypeString = 'manual') THEN

		INSERT INTO gaming_balance_manual_transactions (
			client_id, client_stat_id, payment_transaction_type_id, payment_method_id, balance_account_id, 
			amount, transaction_date, external_reference, reason, notes, 
			user_id, session_id, created_date, request_creator_type_id, request_creator_id,
			payment_reconciliation_status_id, gate_detail_id, payment_file_import_summary_id, transaction_reconcilation_status_id)
		SELECT clientID, clientStatID, payment_transaction_type_id, paymentMethodID, balanceAccountID, 
			varAmount, NOW(), paymentGatewayTransactionKey, NULL, NULL, 
			0, 0, NOW(), 3 /* System type*/,  1 /* user_id of system */,
			NULL, NULL, NULL, 6
		FROM gaming_payment_transaction_type
		WHERE gaming_payment_transaction_type.name='Deposit';
        
        SET balanceManualTransactionID = LAST_INSERT_ID();

	END IF;
  
  UPDATE gaming_balance_history 
  JOIN gaming_payment_transaction_status ON LOWER(gaming_payment_transaction_status.name)=LOWER(transactionStatus)
  JOIN gaming_operator_currency ON gaming_operator_currency.currency_id=gaming_balance_history.currency_id 
  JOIN gaming_client_stats ON gaming_balance_history.client_stat_id=gaming_client_stats.client_stat_id  
  JOIN gaming_balance_accounts ON gaming_balance_accounts.balance_account_id=balanceAccountID
  LEFT JOIN gaming_balance_history_error_codes ON gaming_balance_history_error_codes.error_code=errorCode
  LEFT JOIN gaming_balance_manual_transactions ON gaming_balance_manual_transactions.balance_manual_transaction_id = gaming_balance_history.balance_manual_transaction_id
  SET     
    gaming_balance_history.order_ref=IFNULL(gaming_balance_history.order_ref,orderRef),
    gaming_balance_history.payment_transaction_status_id = gaming_payment_transaction_status.payment_transaction_status_id,
    gaming_balance_history.pending_request = 0,
    gaming_balance_history.timestamp = IF(gaming_balance_history.timestamp IS NULL OR updateClientStatFunds OR refundClientStatFunds, @timestamp, gaming_balance_history.timestamp), 
    gaming_balance_history.sub_payment_method_id = gaming_balance_accounts.sub_payment_method_id,
    gaming_balance_history.balance_account_id = IFNULL(gaming_balance_history.balance_account_id, gaming_balance_accounts.balance_account_id),
    gaming_balance_history.account_reference = IFNULL(gaming_balance_history.account_reference, accountReference), 
    gaming_balance_history.client_stat_balance_updated = IF (client_stat_balance_updated, client_stat_balance_updated, updateClientStatFunds),  
    gaming_balance_history.client_stat_balance_refunded = IF (client_stat_balance_refunded, client_stat_balance_refunded, refundClientStatFunds),
    gaming_balance_history.amount = IF(pendingRequest=1, varAmount, gaming_balance_history.amount),
    gaming_balance_history.amount_base = IF(pendingRequest=1, ROUND(varAmount/exchangeRate,5), gaming_balance_history.amount_base),
    gaming_balance_history.exchange_rate = IF(pendingRequest=1, exchangeRate, gaming_balance_history.exchange_rate),
    gaming_balance_history.balance_real_after = IF (balance_real_after IS NULL OR isRejected OR updateClientStatFunds OR refundClientStatFunds, current_real_balance, balance_real_after),
    gaming_balance_history.balance_bonus_after = IF (balance_bonus_after IS NULL OR isRejected OR updateClientStatFunds OR refundClientStatFunds, current_bonus_balance+current_bonus_win_locked_balance, balance_bonus_after),
    gaming_balance_history.payment_gateway_id = IFNULL(gaming_balance_history.payment_gateway_id, paymentGatewayID),
    gaming_balance_history.payment_gateway_transaction_key = IFNULL(payment_gateway_transaction_key, paymentGatewayTransactionKey),
    gaming_balance_history.is_processed = isProcessed,
    gaming_balance_history.process_at_datetime = IFNULL(process_at_datetime, processAtDatetime),
    gaming_balance_history.is_processed = IF(isProcessed=1, 1, is_processed),
    gaming_balance_history.authorize_now = IF(isProcessed=1, 0, authorize_now),
    gaming_balance_history.cancel_now = IF(isProcessed=1, 0, cancel_now),
    gaming_balance_history.is_processing = IF(isProcessed=1, 0, is_processing),
    gaming_balance_history.is_failed = IF(isProcessed=1, 0, is_failed),
    gaming_balance_history.processed_datetime = IF(isProcessed=1 AND processed_datetime IS NULL, NOW(), processed_datetime),
    gaming_balance_history.balance_history_error_code_id=gaming_balance_history_error_codes.balance_history_error_code_id,
    gaming_balance_history.description = gaming_balance_history_error_codes.message, 
    gaming_balance_history.custom_message = customMessage,
    gaming_balance_history.is_manual_transaction= IF(gaming_balance_manual_transactions.payment_file_import_summary_id IS NULL, isManualTransaction, 0),
    gaming_balance_history.balance_manual_transaction_id=balanceManualTransactionID,
	gaming_balance_history.voucher_code=IFNULL(bonusCode, gaming_balance_history.voucher_code),
    gaming_balance_accounts.last_successful_deposit_date=IF(isAccepted,NOW(),gaming_balance_accounts.last_successful_deposit_date),
    gaming_balance_history.occurrence_num = IF(gaming_balance_history.occurrence_num IS NULL AND updateClientStatFunds, numDeposits, gaming_balance_history.occurrence_num)
  WHERE gaming_balance_history.balance_history_id=balanceHistoryID;

  OPEN redeemCursor;
    allBonusLabel: LOOP  
      
      SET noMoreRecords=0;
      FETCH redeemCursor INTO bonusInstanceID;
      IF (noMoreRecords) THEN
        LEAVE allBonusLabel;
      END IF;
	  IF bonusRedeemAll THEN
		CALL BonusRedeemAllBonus(bonusInstanceID, 0, 0, 'below threshold on deposit','RedeemBonus', null);
	  ELSE
		CALL BonusRedeemBonus(bonusInstanceID, 0, 0, 'below threshold  on deposit','RedeemBonus', null);
	  END IF;

	END LOOP allBonusLabel;
  CLOSE redeemCursor;
  
  IF (updateClientStatFunds) THEN
    CALL BonusCheckAwardingOnDeposit(balanceHistoryID, clientStatID);    
    
    UPDATE gaming_balance_history
    JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
    SET
      balance_real_after=current_real_balance,
      balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
    WHERE gaming_balance_history.balance_history_id=balanceHistoryID;
  END IF;
  
  SELECT gs1.value_bool INTO notificationEnabled
  FROM gaming_settings gs1 
  WHERE gs1.name='NOTIFICATION_ENABLED';
  
  IF (notificationEnabled) THEN
		IF(isRejected) THEN
			
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (51, balanceHistoryID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
		END IF;
		
		IF (updateClientStatFunds) THEN
			
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (50, balanceHistoryID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			
			INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
			VALUES (52, balanceHistoryID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			IF(numDeposits = 1) THEN
				
				INSERT INTO notifications_events (notification_event_type_id, event_id, event2_id, is_processing) 
				VALUES (53, balanceHistoryID, clientID, 0) ON DUPLICATE KEY UPDATE event2_id=VALUES(event2_id), is_processing=VALUES(is_processing);
			END IF;
		END IF;
  END IF;
  
  IF (updateClientStatFunds && retryPlayerSubscription) THEN 
	UPDATE gaming_lottery_auto_play_coupons
	JOIN gaming_lottery_coupons ON gaming_lottery_auto_play_coupons.lottery_coupon_id = gaming_lottery_coupons.lottery_coupon_id
		SET lottery_auto_play_status_id = 5
	WHERE lottery_auto_play_status_id = 3 AND client_stat_id = clientStatID AND coupon_date > DATE_ADD(NOW(), INTERVAL -2 MONTH);
  
  END IF;
  
END root$$

DELIMITER ;

