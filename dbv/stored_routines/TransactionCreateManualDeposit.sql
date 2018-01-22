DROP procedure IF EXISTS `TransactionCreateManualDeposit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionCreateManualDeposit`(
  clientStatID BIGINT, paymentMethodID BIGINT, balanceAccountID BIGINT, varAmount DECIMAL(18, 5), transactionDate DATETIME, externalReference VARCHAR(80), 
  selectedBonusRuleID BIGINT, varReason VARCHAR(1024), varNotes TEXT, userID BIGINT, sessionID BIGINT, bonusCode VARCHAR(80), OUT balanceManualTransactionID BIGINT, platformType VARCHAR(20),uniqueTransactionKey VARCHAR(80), 
  retryPlayerSubscriptions TINYINT(1), OUT statusCode INT, gateDetailID BIGINT, paymentFileImportSummaryID BIGINT,paymentReconciliationStatusID INT, transactionReconcilationStatus VARCHAR(80),
  transactionStatus VARCHAR(80), processedDate DATETIME, isChargeEnabled TINYINT(1), ignoreWalletLimit TINYINT(1))
root: BEGIN

  DECLARE operatorID, clientID, clientStatIDCheck, currencyID, paymentGatewayID, balanceAccountIDCheck, subPaymentMethodID, orderRef, chargeSettingID, creatorTypeID, creatorID BIGINT DEFAULT -1;
  DECLARE paymentGatewayRef, transactionAuthorizedStatusCode INT DEFAULT 0;
  DECLARE currencyCode, paymentGatewayTransactionKey, accountReference, cardHolderName, methodSubType, uniqueTransactionID VARCHAR(255) DEFAULT NULL;
  DECLARE isSuspicious, isTestPlayer, testPlayerAllowTransfers, isCaptureIntervalEnabled, manualDepositRequireAccount,invalidBonusCode, maxBalanceThresholdEnabled, canDeposit, overAmount TINYINT(1) DEFAULT 0;
  DECLARE expiryDate DATETIME DEFAULT NULL;
  DECLARE currentRealBalance, maxPlayerBalanceThreshold, chargeAmount DECIMAL(18,5)  DEFAULT 0;
  SELECT value_bool INTO maxBalanceThresholdEnabled FROM gaming_settings WHERE name='MAXIMUM_PLAYER_EWALLET_BALANCE_THRESHOLD_ENABLED';
  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator=1;
  
  IF (uniqueTransactionKey IS NULL) THEN
	SET uniqueTransactionID = PaymentGetPaymentKeyFromBit8PaymentMethodID(paymentMethodID);
  ELSE
	SET uniqueTransactionID = uniqueTransactionKey;
  END IF;
  
  IF (transactionStatus IS NULL) THEN 
    SET transactionStatus = 'Accepted';
  END IF;
  IF (ignoreWalletLimit IS NULL) THEN
	SET ignoreWalletLimit = 0;
  END IF;						   	 

  SET balanceManualTransactionID=-1;
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SELECT gaming_clients.client_id, gaming_client_stats.client_stat_id, is_suspicious, is_test_player, test_player_allow_transfers, gaming_currency.currency_id, gaming_currency.currency_code, gaming_client_stats.current_real_balance, ifnull(gaming_client_stats.max_player_balance_threshold,gaming_countries.max_player_balance_threshold) as max_player_balance_threshold 
  INTO clientID, clientStatIDCheck, isSuspicious, isTestPlayer, testPlayerAllowTransfers, currencyID, currencyCode, currentRealBalance, maxPlayerBalanceThreshold
  FROM gaming_client_stats 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id 
  JOIN gaming_clients ON gaming_clients.client_id=gaming_client_stats.client_id 
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  LEFT JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id AND clients_locations.is_primary = 1
  LEFT JOIN gaming_countries ON clients_locations.country_id = gaming_countries.country_id 
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 AND (gaming_clients.is_account_closed=0 AND gaming_fraud_rule_client_settings.block_account = 0);
      
  IF (varAmount < 1.0) THEN
    SET statusCode=5;
    LEAVE root;
  END IF;
  
  IF (clientStatIDCheck=-1 OR clientID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (isSuspicious=1 OR (isTestPlayer=1 AND testPlayerAllowTransfers=0)) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
	
 
  IF(ignoreWalletLimit = 0 AND maxBalanceThresholdEnabled = 1 AND NOT ISNULL(maxPlayerBalanceThreshold) AND (maxPlayerBalanceThreshold = 0 OR (currentRealBalance + varAmount > maxPlayerBalanceThreshold))) THEN
  SET statusCode = 6;
    LEAVE root;
  END IF;
 
  SELECT payment_gateway_id, payment_gateway_ref 
  INTO paymentGatewayID, paymentGatewayRef
  FROM gaming_payment_gateways WHERE name='Internal';
  
  IF (paymentGatewayID=-1) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  SELECT payment_method_id, manual_deposit_require_account, can_deposit 
  INTO paymentMethodID, manualDepositRequireAccount, canDeposit
  FROM gaming_payment_method
  WHERE payment_method_id=paymentMethodID;
  
  IF(canDeposit=0) THEN
	SET statusCode=13;
  END IF;
  
  SELECT balance_account_id, account_reference, cc_holder_name, expiry_date, payment_method_id, sub_payment_method_id
  INTO balanceAccountIDCheck, accountReference, cardHolderName, expiryDate, paymentMethodID, subPaymentMethodID
  FROM gaming_balance_accounts
  WHERE balance_account_id=balanceAccountID AND (payment_method_id=paymentMethodID OR sub_payment_method_id=paymentMethodID) AND client_stat_id=clientStatID AND is_active=1
  LIMIT 1;
  
  IF (manualDepositRequireAccount) THEN
    IF (balanceAccountID=-1) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
  END IF;
 
  SET subPaymentMethodID=IF(subPaymentMethodID=-1, paymentMethodID, subPaymentMethodID);
  
  SET transactionDate=IFNULL(transactionDate,NOW());
 
  IF (bonusCode IS NOT NULL && bonusCode !='') THEN 
	SET invalidBonusCode=1;
	SELECT 0 INTO invalidBonusCode FROM gaming_bonus_rules	
	WHERE restrict_by_voucher_code AND is_active =1 AND voucher_code = bonusCode LIMIT 1;
  END IF;
  
  IF (isChargeEnabled = 1) THEN
	CALL PaymentCalculateCharge('Deposit', paymentMethodID, currencyID, varAmount, 0, chargeSettingID, varAmount, chargeAmount, overAmount);
  END IF;
  
  SELECT TransactionCheckDepositAmountWithinLimit(clientStatID, paymentMethodID, varAmount, balanceAccountID) INTO @depositCheckLimitStatus;
  IF (@depositCheckLimitStatus!=0 && transactionStatus = 'Accepted') THEN
	  IF (@depositCheckLimitStatus=1) THEN
		SET statusCode=10;
		LEAVE root;
	  END IF;
  END IF;

  SET @timestamp=NOW();
   
  INSERT INTO gaming_balance_history(client_id, client_stat_id, currency_id, amount_prior_charges, amount_prior_charges_base, charge_amount, unique_transaction_id, payment_method_id, sub_payment_method_id, payment_charge_setting_id, payment_transaction_type_id, pending_request, selected_bonus_rule_id, request_timestamp, is_processed, session_id, voucher_code, platform_type_id, retry_player_subscriptions, issue_withdrawal_type_id)
  SELECT clientID, clientStatID, currencyID, varAmount, ROUND(varAmount/gaming_operator_currency.exchange_rate,5), chargeAmount, uniqueTransactionID, paymentMethodID, subPaymentMethodID, chargeSettingID, gaming_payment_transaction_type.payment_transaction_type_id, 1, IFNULL(selectedBonusRuleID,-1), @timestamp, 0, sessionID, bonusCode, gaming_platform_types.platform_type_id , retryPlayerSubscriptions, 
	(SELECT issue_withdrawal_type_id FROM gaming_issue_withdrawal_types WHERE `name` = 'No-Withdrawal') 
  FROM gaming_payment_transaction_type 
  JOIN gaming_operator_currency ON gaming_payment_transaction_type.name='Deposit' AND gaming_operator_currency.operator_id=operatorID AND gaming_operator_currency.currency_id=currencyID
  LEFT JOIN gaming_platform_types ON gaming_platform_types.platform_type=platformType;
  
  SET creatorTypeID = CASE 
	WHEN userID > 1 /* Operator */ THEN 2 /* User type */
	WHEN userID = 0 /* Player */ THEN 1 /* Player type */
	ELSE 3 /* System type*/
  END;
  
  SET creatorID = IF (userID > 0, userID, clientID);
  
  INSERT INTO gaming_balance_manual_transactions (
	client_id, client_stat_id, payment_transaction_type_id, payment_method_id, balance_account_id, 
	amount, charge_amount, payment_charge_setting_id, transaction_date, external_reference, 
	reason, notes, user_id, session_id,
	created_date, request_creator_type_id, request_creator_id,
	payment_reconciliation_status_id, gate_detail_id, payment_file_import_summary_id, transaction_reconcilation_status_id, processed_date)
  SELECT clientID, clientStatID, payment_transaction_type_id, paymentMethodID, balanceAccountID, 
	varAmount, chargeAmount, chargeSettingID, transactionDate, externalReference, 
	varReason, varNotes, userID, sessionID, 
	@timestamp, creatorTypeID, creatorID,
	paymentReconciliationStatusID, gateDetailID, paymentFileImportSummaryID, transaction_reconcilation_status_id, processedDate
  FROM gaming_payment_transaction_type
  LEFT JOIN gaming_transaction_reconcilation_statuses ON gaming_transaction_reconcilation_statuses.name = transactionReconcilationStatus
  WHERE gaming_payment_transaction_type.name='Deposit';
  
  SET balanceManualTransactionID=LAST_INSERT_ID();
  
  SET isCaptureIntervalEnabled=0;
  SET methodSubType=NULL; 
  SET paymentGatewayTransactionKey=externalReference;
  SET orderRef=NULL;
  CALL TransactionProcessDepositAuthorized(isCaptureIntervalEnabled, orderRef, transactionStatus, 0, @timestamp, accountReference, methodSubType, clientID, uniqueTransactionID, varAmount, currencyCode, paymentGatewayRef, paymentGatewayTransactionKey, cardHolderName, expiryDate, null, varReason, balanceManualTransactionID, null, transactionAuthorizedStatusCode);
  
  IF (balanceAccountID IS NULL) THEN
    UPDATE gaming_balance_manual_transactions 
    JOIN gaming_balance_history ON gaming_balance_history.unique_transaction_id=uniqueTransactionID AND gaming_balance_history.client_stat_id=clientStatID
    SET gaming_balance_manual_transactions.balance_account_id=gaming_balance_history.balance_account_id
    WHERE gaming_balance_manual_transactions.balance_manual_transaction_id=balanceManualTransactionID;
  END IF;

  SELECT invalidBonusCode AS invalid_bonus_amount;
  
  SET statusCode=IF(transactionAuthorizedStatusCode=0,0,transactionAuthorizedStatusCode+10);
END root$$

DELIMITER ;

