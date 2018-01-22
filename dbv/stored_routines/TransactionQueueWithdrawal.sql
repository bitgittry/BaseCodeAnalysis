DROP procedure IF EXISTS `TransactionQueueWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionQueueWithdrawal`(sessionID BIGINT, clientStatID BIGINT, balanceAccountID BIGINT, varAmount DECIMAL(18, 5), varReason TEXT, isCashback TINYINT(1), charge TINYINT(1),requestedByUser TINYINT(1), paymentKey VARCHAR(80), newAccountReference VARCHAR(80), issueWithdrawalType VARCHAR(20), processDateTime DATETIME, ignoreWithdrawalChecks TINYINT(1), OUT statusCode INT)
root: BEGIN

/* Status Codes
* 0 - Success 
* 1 - ClientStatID not found 
* 2 - OperatorCurrency does not exists
* 3 - Insufficient funds 
* 4 - BalanceAccountID not found or in-active
* 5 - withdraw limits exceeded - amount too low
* 6 - withdraw limits exceeded - amount too high
* 7 - unknown error while inserting into balance_history
* 8 - TransactionCheckWithdrawAmountWithinLimit: returned invalid payment_method_id
* 9 - Payment Method for player is disabled
* 10 - Payment Method requires that the client payment information is validated typically by doing a deposit but none has been done yet.
* 11 - Player is not allowed to affect transfers (either IsSuspicious or IsTestPlayer)
* 12 - Player is not allowed to affect transfers (deposit & withdrawal) by fraud engine
* 13 - Player is not allowed to affect transfers (deposit & withdrawal) due to player restrictions
* 14 - Restrict Withdrawals to only winnings is active and funds are insufficient
* 15 - KYC Verification Required 
* 16 - Insufficient player funds. Withdrawal amount exceeds the Provisional Real Money Balance.
* 17 - Player Payment Method Required Attributes For Withdrawal are invalid or not present.
* 18 - Deposit Required before withdrawal 
*/
  
  -- Overriding account_refernce in gaming_balance_accounts
  -- added check not to insert into gaming_balance_history but update if there is already an entry with the same payment key
  -- Added push notification: IF(statusCode=0, WithdrawalRequest, WithdrawalRejected)  
  -- Payment Key using the Bit8 function instead of UUID().
  -- Fixed bug by setting gaming_balance_withdrawal_requests.withdrawal_session_ket to NULL if storePaymentKeyInWithrawalRequest=0 
  -- Added issueWithdrawalType management - CPREQ-36
  -- Added ignoreWithdrawalChecks - CPREQ-36
  -- Added updating of creatorTypeID (Player or User or System) and creatorID (client_id or user_id) values - CPREQ-329
  
  
  DECLARE operatorID, balanceHistoryID, clientStatIDCheck, clientID, clientIDCheck, currencyID, currencyIDCheck, clientSegmentID, 
	balanceAccountIDCheck, paymentMethodID, paymentSubMethodID, paymentMethodGroupID, balanceWithdrawalRequestID, 
	numRestrictions, balanceManualTransactionID, requiredForWithdrawalAttributes, chargeSettingID, creatorTypeID, creatorID BIGINT DEFAULT -1;
  
  DECLARE currentRealBalance, exchangeRate, totalRealWon, totalBonusTransferred, totalBonusWinLockedTransferred, 
	withdrawnAmount, withdrawalPendingAmount, deferredTax, calculatedAmount, chargeAmount DECIMAL(18, 5) DEFAULT 0;
    
  DECLARE isSuspicious, isTestPlayer, testPlayerAllowTransfers, isWaitingKYC, requireClientInfo, 
	isValidated, isDisabled, isCountryDisabled, fraudEnabled, fraudOnDepositEnabled, dissallowTransfer, playerRestrictionEnabled, balanceAccountActiveFlag, 
    disableSaveAccountBalance, withdrawalAllowed, getAccountIDFOnWithdraw, notificationEnabled, restrictWithdrawalsToOnlyWinnings, 
    kycReturnError, taxEnabled, launchCashier, overAmount, canWithdaw, disallowWithdrawBeforeDeposit TINYINT(1) DEFAULT 0;
    
  DECLARE checkWithdrawLimitReturn, errorCode, hasFraudRows INT DEFAULT 0;
  DECLARE paymentMethodName, accountReference, uniqueTransactionIDLast, paymentGatewayName VARCHAR(80) DEFAULT NULL;
  DECLARE paymentGroupWithdrawalAllowed TINYINT(1) DEFAULT 1;
  DECLARE paymentMethodIntegrationTypeString VARCHAR(80) DEFAULT NULL;
  DECLARE paymentGatewayNameForMyriad VARCHAR(80) DEFAULT NULL;
  DECLARE maxAllowedWithdrawals, finalMaximumammount, totalPaymentDeposits DECIMAL(18, 5) DEFAULT 0;
  DECLARE storePaymentKeyInWithrawalRequest TINYINT(1) DEFAULT 9;
 
 
  SET statusCode=0;
  
  SELECT client_stat_id, gaming_clients.client_id, is_suspicious, withdrawal_allowed, is_test_player, test_player_allow_transfers, client_segment_id, current_real_balance, gaming_client_stats.currency_id, total_real_won, total_bonus_transferred, total_bonus_win_locked_transferred, withdrawn_amount, withdrawal_pending_amount, deferred_tax
  INTO clientStatIDCheck, clientID, isSuspicious, withdrawalAllowed, isTestPlayer, testPlayerAllowTransfers, clientSegmentID, currentRealBalance, currencyID, totalRealWon, totalBonusTransferred, totalBonusWinLockedTransferred, withdrawnAmount, withdrawalPendingAmount, deferredTax
  FROM gaming_client_stats 
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 AND (gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL))
  FOR UPDATE;
  
  SET @UnlockedNWFunds = 0;
  
  IF (clientStatIDCheck=-1 OR clientID=-1) THEN
    SET statusCode=1;
  
  ELSEIF (isSuspicious=1 OR withdrawalAllowed=0 OR (isTestPlayer=1 AND testPlayerAllowTransfers=0)) THEN
    SET statusCode=11;
  END IF;
  
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;
  
  SELECT currency_id, exchange_rate INTO currencyIDCheck, exchangeRate
  FROM gaming_operator_currency 
  WHERE gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.currency_id=currencyID;
  
  IF (currencyIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  IF (statusCode=0) THEN
    SELECT balance_account_id, gaming_payment_method.payment_method_id, gaming_payment_method.name, subpayment.payment_method_id, 
		subpayment.payment_method_group_id, gaming_balance_accounts.is_active, account_reference, unique_transaction_id_last, 
		gaming_payment_method.get_account_idf_on_withdraw, gaming_payment_gateways.`name` as `payment_gateway`, pmit.name,
        IF(gaming_payment_method.can_withdraw_without_payment_account, gaming_client_stats.deposited_amount > 0, gaming_balance_accounts.can_withdraw) AS can_withdraw
    INTO balanceAccountIDCheck, paymentMethodID, paymentMethodName, paymentSubMethodID, paymentMethodGroupID, 
		balanceAccountActiveFlag, accountReference, uniqueTransactionIDLast, getAccountIDFOnWithdraw, 
        paymentGatewayNameForMyriad, paymentMethodIntegrationTypeString,
        canWithdaw
    FROM gaming_balance_accounts
    JOIN gaming_client_stats ON gaming_balance_accounts.client_stat_id=gaming_client_stats.client_stat_id
    JOIN gaming_payment_method ON gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
	JOIN gaming_payment_method subpayment ON gaming_balance_accounts.sub_payment_method_id=subpayment.payment_method_id
	LEFT JOIN gaming_payment_method_integration_types pmit ON pmit.payment_method_integration_type_id = gaming_payment_method.payment_method_integration_type_id
    LEFT JOIN gaming_payment_gateways ON gaming_payment_gateways.payment_gateway_id = gaming_balance_accounts.payment_gateway_id
    WHERE gaming_balance_accounts.balance_account_id=balanceAccountID;
    
    IF (balanceAccountIDCheck=-1) THEN
      SET statusCode=4;
    ELSEIF (balanceAccountActiveFlag=0) THEN
      SET statusCode=4;
    END IF;
    
    SELECT value_bool INTO disallowWithdrawBeforeDeposit FROM gaming_settings WHERE name='TRANSACTION_DISALLOW_WITHDRAWAL_ON_REQUEST_UNTIL_DEPOSIT';
    
    IF (disallowWithdrawBeforeDeposit AND canWithdaw=0) THEN
		SET statusCode=18;
    END IF;
    
    SELECT value_bool INTO fraudEnabled FROM gaming_settings WHERE name='FRAUD_ENABLED';
    
    -- EcoCard/Neteller: the cents are removed when not Myriad -- MLK HOT-FIX
    IF (paymentMethodName IN ('EcoCard','Neteller') AND ('Myriad' != paymentGatewayNameForMyriad)) THEN
      SET varAmount=ROUND(FLOOR(varAmount/100)*100,0);
    END IF;
    
    IF (uniqueTransactionIDLast IS NOT NULL AND accountReference<>'Account') THEN
      SELECT gaming_payment_gateways.name, gaming_payment_gateways.disable_save_account_balance 
      INTO paymentGatewayName, disableSaveAccountBalance
      FROM gaming_balance_history
      JOIN gaming_payment_gateways ON gaming_balance_history.payment_gateway_id=gaming_payment_gateways.payment_gateway_id
      WHERE gaming_balance_history.unique_transaction_id=uniqueTransactionIDLast;
      
      IF (paymentGatewayName IS NOT NULL AND paymentGatewayName='External' AND disableSaveAccountBalance=1) THEN
        UPDATE gaming_balance_accounts SET unique_transaction_id_last=NULL WHERE balance_account_id=balanceAccountID;
        CALL PaymentCreateDummyPurchaseForWithdrawal(balanceAccountID, NULL, @dps);
      END IF;
    END IF;
  END IF;
  
  IF (statusCode=0) THEN
    SELECT gaming_payment_method.require_client_info, IFNULL(gaming_client_payment_info.is_validated, 0), IFNULL(gaming_client_payment_info.is_disabled, 0),
		IFNULL(country_payment_permissions.is_disabled=1 OR country_payment_permissions.is_withdrawal_disabled=1, 0)
    INTO requireClientInfo, isValidated, isDisabled, isCountryDisabled
    FROM gaming_client_stats FORCE INDEX (PRIMARY)
    STRAIGHT_JOIN gaming_payment_method ON gaming_payment_method.payment_method_id=paymentMethodID
	STRAIGHT_JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id
    LEFT JOIN gaming_client_payment_info ON gaming_client_payment_info.client_id=gaming_client_stats.client_id  AND gaming_client_payment_info.payment_method_id=gaming_payment_method.payment_method_id
    LEFT JOIN clients_locations ON clients_locations.client_id=gaming_clients.client_id AND clients_locations.is_primary=1
    LEFT JOIN gaming_country_payment_info AS country_payment_permissions ON 
		country_payment_permissions.country_id=clients_locations.country_id AND country_payment_permissions.payment_method_id=gaming_payment_method.payment_method_id
    WHERE gaming_client_stats.client_stat_id=clientStatID;
  
    IF (isDisabled OR isCountryDisabled) THEN 
      SET statusCode=9;
    ELSEIF (requireClientInfo AND isValidated=0) THEN 
      SET statusCode=10;
    END IF;
  END IF;

 IF (statusCode=0) THEN
	SELECT COUNT(1) INTO requiredForWithdrawalAttributes
	FROM gaming_payment_method
	STRAIGHT_JOIN payment_methods ON gaming_payment_method.payment_gateway_method_name=payment_methods.name AND 
		((gaming_payment_method.payment_gateway_method_sub_name IS NULL AND payment_methods.sub_name IS NULL) OR gaming_payment_method.payment_gateway_method_sub_name=payment_methods.sub_name)
	JOIN payment_profiles ON payment_profiles.payment_profile_id=payment_methods.payment_profile_id
	JOIN payment_gateway_methods AS pgm ON payment_profiles.payment_gateway_id=pgm.payment_gateway_id AND payment_methods.payment_method_id=pgm.payment_method_id AND pgm.country_code IS NULL
	JOIN payment_gateway_methods_attributes AS pgma ON pgm.payment_gateway_method_id=pgma.payment_gateway_method_id AND pgma.required_for_withdrawal = 1
	JOIN payment_gateway_method_attributes AS pgma2 ON pgma2.attr_name = pgma.attr_name
	LEFT JOIN gaming_balance_account_attributes ON gaming_balance_account_attributes.balance_account_id = balanceAccountID AND 
		gaming_balance_account_attributes.attr_name = pgma2.attr_name 
	WHERE gaming_payment_method.payment_method_id=paymentMethodID AND gaming_balance_account_attributes.balance_account_id IS NULL;
	
	IF (requiredForWithdrawalAttributes > 0) THEN
        SET statusCode=17;
	END IF;
 END IF;

  
  IF (statusCode=0) THEN
    IF (0 = ignoreWithdrawalChecks) THEN
    SELECT value_bool INTO fraudEnabled FROM gaming_settings WHERE name='FRAUD_ENABLED';
    SELECT value_bool INTO fraudOnDepositEnabled FROM gaming_settings WHERE name='FRAUD_ON_DEPOSIT_ENABLED';
    
	IF (fraudEnabled=1 AND fraudOnDepositEnabled=1) THEN
      
      SET clientIDCheck=-1;
      SET dissallowTransfer=0;
	  SET paymentGroupWithdrawalAllowed=1;
	  
					  
																			   
	  SELECT client_id, disallow_transfers, IFNULL(withdrawal_allowed,1), COUNT(*)
	  INTO clientIDCheck, dissallowTransfer, paymentGroupWithdrawalAllowed, hasFraudRows
												  
	  JOIN gaming_fraud_classification_types ON 
        cl_events.client_id=clientID AND cl_events.is_current=1 AND
        cl_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id
      LEFT JOIN gaming_fraud_classification_payment_groups gfcpg ON 
		gaming_fraud_classification_types.fraud_classification_type_id = gfcpg.fraud_classification_type_id AND gfcpg.payment_method_group_id = paymentMethodGroupID;
	
	/* If there is no record in the gaming_fraud_classification_payment_groups for the fraud_classification_type_id and the payment_method_group_id
	* then treat deposit and withdrawals as allowed by default
	*/
      IF (hasFraudRows > 0 AND (clientIDCheck=-1 OR dissallowTransfer OR paymentGroupWithdrawalAllowed = 0)) THEN
        SET statusCode=12;
      END IF;
    END IF;
  END IF;
  END IF;
  
  IF (statusCode=0) THEN
    IF (0 = ignoreWithdrawalChecks) THEN
    SELECT value_bool INTO playerRestrictionEnabled FROM gaming_settings WHERE name='PLAYER_RESTRICTION_ENABLED';
    
    IF (playerRestrictionEnabled=1) THEN
      SET numRestrictions=0;
      SELECT COUNT(*) INTO numRestrictions
      FROM gaming_player_restrictions
      JOIN gaming_player_restriction_types AS restriction_types ON restriction_types.is_active=1 AND restriction_types.disallow_transfers=1 AND gaming_player_restrictions.player_restriction_type_id=restriction_types.player_restriction_type_id
      WHERE gaming_player_restrictions.client_id=clientID AND gaming_player_restrictions.is_active=1 AND NOW() BETWEEN restrict_from_date AND restrict_until_date;
      
      IF (numRestrictions > 0) THEN
        SET statusCode=13;
        LEAVE root;
      END IF;
    END IF;
  END IF;
  END IF;
  
   SET calculatedAmount = varAmount;
   IF(charge=1) THEN
	 CALL PaymentCalculateCharge('Withdrawal', paymentMethodID, currencyID, varAmount, 0, chargeSettingID, calculatedAmount, chargeAmount, overAmount);
	 SET varAmount = calculatedAmount + chargeAmount;
   END IF;
   
  IF (statusCode=0 AND isCashback=0) THEN

 
			 
 
			
    IF (currentRealBalance<varAmount) THEN
		  SET statusCode=3;
	  END IF;

    SELECT value_bool INTO taxEnabled FROM gaming_settings WHERE name='TAX_ON_GAMEPLAY_ENABLED';
    
    IF(taxEnabled = 1 and deferredTax > 0) THEN
		    IF((currentRealBalance - deferredTax) < varAmount) THEN
			    SET statusCode=16;
        END IF;
	  END IF;

    SELECT value_bool INTO restrictWithdrawalsToOnlyWinnings FROM gaming_settings WHERE name='PLAYER_RESTRICT_WITHDRAWALS_TO_ONLY_WINNINGS';
    IF (ignoreWithdrawalChecks=0 AND restrictWithdrawalsToOnlyWinnings=1 AND requestedByUser=0) THEN
			IF (CalculateWithdrawableAmount(clientStatID)<varAmount) THEN
			  SET statusCode=14;
		  END IF;    
	  END IF;

  END IF;
  
  IF (statusCode=0 AND isTestPlayer=0) THEN
    IF (0 = ignoreWithdrawalChecks) THEN

    SET checkWithdrawLimitReturn = (SELECT TransactionCheckWithdrawAmountWithinLimit(clientStatID, paymentSubMethodID, varAmount, balanceAccountID)); 
    
    IF (checkWithdrawLimitReturn = 0 AND paymentSubMethodID!=paymentMethodID) THEN
		SET checkWithdrawLimitReturn = (SELECT TransactionCheckWithdrawAmountWithinLimit(clientStatID, paymentMethodID, varAmount, balanceAccountID)); 
    END IF;
    
    IF (checkWithdrawLimitReturn=4) THEN
    
	   SELECT value_bool INTO kycReturnError FROM gaming_settings WHERE name='TRANSFER_KYC_REQUIRED_RETURN_ERROR_ON_WITHDRAWAL';
    
		IF (kycReturnError=0) THEN
		  SET isWaitingKYC=IF(isCashback=1, 0, 1); 
		  SET checkWithdrawLimitReturn=0;
		END IF;
        
    ELSE
      SET isWaitingKYC=0;
    END IF;
    
    IF (checkWithdrawLimitReturn<>0) THEN
      CASE checkWithdrawLimitReturn
        WHEN 1 THEN SET statusCode=8;
        WHEN 2 THEN SET statusCode=5;
        WHEN 3 THEN SET statusCode=6;
        WHEN 4 THEN SET statusCode=15; 
        ELSE SET statusCode=100; 
      END CASE;    
    END IF;
  END IF;
  END IF;
  
  IF (statusCode=0) THEN
    SET @paymentTransactionStatus='Pending';
    SET @clientStatBalanceUpdated=1;
    
    UPDATE gaming_client_stats 
    SET current_real_balance=current_real_balance-varAmount, withdrawal_pending_amount=withdrawal_pending_amount+calculatedAmount,
        first_withdrawn_date=IFNULL(first_withdrawn_date, NOW()), last_withdrawn_date=NOW(), num_withdrawals=num_withdrawals+1,
        locked_real_funds = locked_real_funds -  (@UnlockedNWFunds := (IF (current_real_balance<locked_real_funds,locked_real_funds - current_real_balance, 0))),
		withdrawn_pending_charge_amount=withdrawn_pending_charge_amount+chargeAmount
    WHERE gaming_client_stats.client_stat_id=clientStatID;
    
    UPDATE gaming_balance_accounts
    SET withdrawal_pending_amount=withdrawal_pending_amount+calculatedAmount, date_last_used=NOW(), 
		account_reference=IF(getAccountIDFOnWithdraw AND IFNULL(accountReference,'Account')='Account' AND newAccountReference IS NOT NULL, newAccountReference, account_reference),
		withdrawn_pending_charge_amount=withdrawn_pending_charge_amount+chargeAmount
    WHERE balance_account_id=balanceAccountID;
    
    SET errorCode=0;
  ELSE
    SET @paymentTransactionStatus='Rejected';
    SET @clientStatBalanceUpdated=0;
    
    SET errorCode =     
      CASE statusCode
        WHEN 1  THEN 10 
        WHEN 2  THEN 10 
        WHEN 3  THEN 18 
        WHEN 4  THEN 19 
        WHEN 5  THEN 12 
        WHEN 6  THEN 6  
        WHEN 7  THEN 10 
        WHEN 8  THEN 9  
        WHEN 9  THEN 14 
        WHEN 10 THEN 15 
        WHEN 11 THEN 3  
        WHEN 12 THEN 4  
        WHEN 13 THEN 11 
        WHEN 14 THEN 27
        WHEN 15 THEN 8
		WHEN 16 THEN 28
        WHEN 18 THEN 29
        ELSE 10 
      END;
  END IF;
    
  SET @paymentTransactionType=IF(isCashback=0,'Withdrawal','Cashback');
  SET @timestamp=NOW();
  
  IF (paymentKey IS NOT NULL) THEN
	SELECT balance_history_id INTO balanceHistoryID FROM gaming_balance_history WHERE unique_transaction_id=paymentKey AND client_stat_id=clientStatID;
  END IF;
 
  IF (paymentKey IS NULL) THEN 
	-- SET paymentKey=UUID(); -- Before
	SET paymentKey=PaymentGetPaymentKeyFromBit8PaymentMethodID(paymentMethodID);
	SET storePaymentKeyInWithrawalRequest=0;
  ELSE
	SET storePaymentKeyInWithrawalRequest=1;
  END IF;
  
  SELECT CASE 
		WHEN giwt.issue_withdrawal_type_id = 2 /* Operator */ AND s.user_id > 1 THEN 2 /* User type */
		WHEN giwt.issue_withdrawal_type_id = 3 /* Player */ THEN 1 /* Player type */
		ELSE 3 /* System type*/
	END,
  CASE 
		WHEN giwt.issue_withdrawal_type_id = 2 /* Operator */ AND s.user_id > 1 THEN s.user_id
		WHEN giwt.issue_withdrawal_type_id = 3 /* Player */ THEN IFNULL(s.extra_id, clientID) /* client_id */
		ELSE 1 /* user_id of system */
	END
  INTO creatorTypeID, creatorID
  FROM gaming_issue_withdrawal_types AS giwt
  LEFT JOIN sessions_main AS s ON s.session_id = sessionID
  WHERE giwt.`name` = issueWithdrawalType LIMIT 1;
  
  IF (paymentMethodIntegrationTypeString = 'manual') THEN

	INSERT INTO gaming_balance_manual_transactions( 
		client_id, client_stat_id, payment_transaction_type_id, payment_method_id, balance_account_id, 
		amount, transaction_date, external_reference, reason, notes, user_id, session_id, 
		created_date, request_creator_type_id, request_creator_id,
		payment_reconciliation_status_id, gate_detail_id, payment_file_import_summary_id, transaction_reconcilation_status_id)
	SELECT clientID, clientStatID, payment_transaction_type_id, paymentMethodID, balanceAccountID, 
		varAmount, NOW(), NULL, NULL, NULL, 0, 0, 
		NOW(), creatorTypeID, creatorID,
		NULL, NULL, NULL, 6
	FROM gaming_payment_transaction_type
	WHERE gaming_payment_transaction_type.name='Withdrawal';
        
    SET balanceManualTransactionID = LAST_INSERT_ID();

  END IF; 

  IF (balanceHistoryID=-1) THEN
	  INSERT INTO gaming_balance_history(
		client_id, client_stat_id, currency_id, amount_prior_charges, amount_prior_charges_base, amount, amount_base, exchange_rate, 
		balance_real_after, balance_bonus_after, balance_account_id, account_reference, unique_transaction_id, payment_method_id, sub_payment_method_id,
		payment_transaction_type_id, payment_transaction_status_id, pending_request, request_timestamp, timestamp, session_id, custom_message, client_stat_balance_updated, balance_history_error_code_id, description, balance_manual_transaction_id, issue_withdrawal_type_id, charge_amount, charge_amount_base ,payment_charge_setting_id)
	  SELECT 
		gaming_client_stats.client_id, clientStatID, currencyID, calculatedAmount, ROUND(calculatedAmount/exchangeRate,5), calculatedAmount, ROUND(calculatedAmount/exchangeRate,5), exchangeRate,
		current_real_balance AS balance_real_after, current_bonus_balance+current_bonus_win_locked_balance AS balance_bonus_after, 
		balanceAccountID, gaming_balance_accounts.account_reference, paymentKey, gaming_balance_accounts.payment_method_id, gaming_balance_accounts.sub_payment_method_id,
		gaming_payment_transaction_type.payment_transaction_type_id, gaming_payment_transaction_status.payment_transaction_status_id, 0, @timestamp , @timestamp, sessionID, varReason, @clientStatBalanceUpdated,
		error_codes.balance_history_error_code_id, error_codes.message, balanceManualTransactionID,
        (SELECT issue_withdrawal_type_id FROM gaming_issue_withdrawal_types WHERE `name` = issueWithdrawalType),chargeAmount, ROUND(chargeAmount/exchangeRate,5),chargeSettingID
	  FROM gaming_client_stats  
	  JOIN gaming_payment_transaction_type ON gaming_client_stats.client_stat_id=clientStatID AND gaming_payment_transaction_type.name=@paymentTransactionType
	  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name=@paymentTransactionStatus
	  LEFT JOIN gaming_balance_accounts ON gaming_balance_accounts.balance_account_id=balanceAccountID  
	  LEFT JOIN gaming_balance_history_error_codes AS error_codes ON error_codes.error_code=errorCode;
	  
	  IF (ROW_COUNT() <> 1) THEN
		SET statusCode=7;
		LEAVE root;
	  END IF;  
	  
	  SET balanceHistoryID=LAST_INSERT_ID();
  ELSE
	UPDATE gaming_balance_history
	  JOIN gaming_client_stats ON gaming_balance_history.client_stat_id=gaming_client_stats.client_stat_id
	  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@paymentTransactionType
	  JOIN gaming_payment_transaction_status ON gaming_payment_transaction_status.name=@paymentTransactionStatus
	  LEFT JOIN gaming_balance_accounts ON gaming_balance_accounts.balance_account_id=balanceAccountID  
	  LEFT JOIN gaming_balance_history_error_codes AS error_codes ON error_codes.error_code=errorCode
	SET gaming_balance_history.balance_account_id=balanceAccountID, gaming_balance_history.account_reference=gaming_balance_accounts.account_reference, 
		gaming_balance_history.exchange_rate=exchangeRate, gaming_balance_history.timestamp=@timestamp, gaming_balance_history.pending_request=0, gaming_balance_history.session_id=sessionID,
		gaming_balance_history.amount_prior_charges=calculatedAmount, gaming_balance_history.amount_prior_charges_base=ROUND(calculatedAmount/exchangeRate,5), 
		gaming_balance_history.amount=calculatedAmount, gaming_balance_history.amount_base=ROUND(calculatedAmount/exchangeRate,5), 
		gaming_balance_history.balance_real_after=gaming_client_stats.current_real_balance, gaming_balance_history.balance_bonus_after=gaming_client_stats.current_bonus_balance+gaming_client_stats.current_bonus_win_locked_balance, 
		gaming_balance_history.payment_transaction_status_id=gaming_payment_transaction_status.payment_transaction_status_id, gaming_balance_history.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id,
		gaming_balance_history.client_stat_balance_updated=@clientStatBalanceUpdated, 
		gaming_balance_history.payment_method_id=gaming_balance_accounts.payment_method_id, gaming_balance_history.sub_payment_method_id=gaming_balance_accounts.sub_payment_method_id,
		gaming_balance_history.balance_history_error_code_id=error_codes.balance_history_error_code_id, gaming_balance_history.description=error_codes.message,
        balance_manual_transaction_id = balanceManualTransactionID,
		charge_amount = chargeAmount,
		payment_charge_setting_id = chargeSettingID,
		charge_amount_base = ROUND(chargeAmount/exchangeRate,5)
	WHERE gaming_balance_history.balance_history_id=balanceHistoryID;

  END IF;

	-- IF(statusCode=0, WithdrawalRequest, WithdrawalRejected)
  SET @notificationTypeID = IF(statusCode=0, 512, 514);
  CALL NotificationEventCreate(@notificationTypeID, balanceHistoryID, clientID, 0);         

  IF (statusCode <> 0) THEN
    LEAVE root;
  END IF;
  
  IF (@clientStatBalanceUpdated=1) THEN
    INSERT INTO gaming_event_rows (event_table_id, elem_id) 
    SELECT 2, balanceHistoryID
    ON DUPLICATE KEY UPDATE elem_id=VALUES(elem_id);
  END IF;
  
  SET @transactionType=IF(isCashback=0,'WithdrawalRequest','Cashback');

  INSERT INTO gaming_transactions
    (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, balance_history_id, reason, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, varAmount*-1, ROUND((varAmount*-1)/exchangeRate, 5), gaming_client_stats.currency_id, exchangeRate, varAmount*-1, 0, 0, 0, 0, @timestamp, gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, paymentMethodID, balanceHistoryID, varReason , pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`) 
  FROM gaming_client_stats 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@transactionType
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SET @transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus,released_locked_funds) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus, @UnlockedNWFunds
  FROM gaming_transactions
  WHERE transaction_id=@transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());
  
  INSERT INTO gaming_balance_withdrawal_requests (
	client_stat_id, balance_account_id, amount, amount_base, 
	request_datetime, request_creator_type_id, request_creator_id, process_at_datetime, 
	is_processed, is_waiting_kyc, balance_withdrawal_request_status_id, balance_history_id, session_id, notes, 
	payment_transaction_type_id, withdrawal_session_key, charge_amount, charge_amount_base, is_semi_automated_withdrawal)
  SELECT clientStatID, balanceAccountID, calculatedAmount, ROUND(calculatedAmount/exchangeRate,5), 
	NOW(), creatorTypeID, creatorID, IFNULL(processDateTime, DATE_ADD(NOW(), INTERVAL gaming_client_segments.withdrawal_interval_minutes MINUTE)), 
	0, isWaitingKYC, gaming_balance_withdrawal_request_statuses.balance_withdrawal_request_status_id, balanceHistoryID, sessionID, IF(requestedByUser,IFNULL(varReason,'Invoked By Operator'),NULL), 
    gaming_payment_transaction_type.payment_transaction_type_id, IF (storePaymentKeyInWithrawalRequest=1, paymentKey, NULL),chargeAmount, ROUND(chargeAmount/exchangeRate,5),
    IF(paymentMethodIntegrationTypeString = 'semi_automated', 1, 0)
  FROM gaming_client_segments
  JOIN gaming_balance_withdrawal_request_statuses ON gaming_balance_withdrawal_request_statuses.name='ManuallyBlocked'
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name=@paymentTransactionType
  WHERE client_segment_id=clientSegmentID;
  
  SET balanceWithdrawalRequestID=LAST_INSERT_ID(); 
  
  CALL BonusCheckLossOnWithdraw(balanceHistoryID, clientStatID);
  
  UPDATE gaming_balance_history
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
  SET
    balance_real_after=current_real_balance,
    balance_bonus_after=current_bonus_balance+current_bonus_win_locked_balance
  WHERE gaming_balance_history.balance_history_id=balanceHistoryID;
 
SELECT payment_gateway_methods.launch_cashier_on_withdrawal
  INTO launchCashier
  FROM gaming_balance_accounts
  STRAIGHT_JOIN payment_purchases ON payment_purchases.payment_key=gaming_balance_accounts.unique_transaction_id_last
  STRAIGHT_JOIN payment_profiles ON payment_purchases.payment_profile_id=payment_profiles.payment_profile_id
  STRAIGHT_JOIN payment_gateway_methods ON 
 payment_gateway_methods.payment_gateway_id=payment_profiles.payment_gateway_id AND
 payment_gateway_methods.payment_method_id=payment_purchases.payment_method_id
  WHERE gaming_balance_accounts.balance_account_id=balanceAccountID
  LIMIT 1;
  
  SELECT balanceWithdrawalRequestID AS balance_withdrawal_request_id, launchCashier AS launch_cashier;
 
  SET statusCode=0;
  
END root$$

DELIMITER ;

