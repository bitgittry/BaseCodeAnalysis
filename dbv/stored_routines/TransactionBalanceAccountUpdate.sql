DROP procedure IF EXISTS `TransactionBalanceAccountUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionBalanceAccountUpdate`(
  balanceAccountID BIGINT, clientStatID BIGINT, accountReference VARCHAR(80), cardHolderName VARCHAR(80), 
  expiryDate DATE, paymentMethodID BIGINT, isActive TINYINT(1), fraudCheckable TINYINT(1), kycChecked TINYINT(1), sessionID BIGINT, userID BIGINT, token VARCHAR(100), 
  paymentGateway VARCHAR(20), isRetrievalMode TINYINT(1), getGatewayFromPaymentMethodProfile TINYINT(1), modifierEntityType VARCHAR(45),
isInternal TINYINT(1), isDefaultWithdrawal TINYINT(1), canWithdraw TINYINT(1), OUT newBalanceAccountID BIGINT, OUT statusCode INT)
root: BEGIN
  
  -- Added Payment Gateway. 
  -- Added Check if paymentMethodID is not passed .
  -- Added Check on balance account update that if subPaymentMehodID is the same as paymentMethodID do not change.
  -- Removed Check with StatusCode: 3, which checks if the account balance already exists. If exists it is updated.
  -- Added Push Notification
  -- Changed calling Push Notification
  -- Added is_default_withdrawal management - CPREQ-36
  -- Added check on balance account creation that if the payment gateway is not supplied it defaults to Internal gateway
  -- Fixed bug and now on update if the gateway is not supplied then it is not changed
  -- Added parameter getGatewayFromPaymentMethodProfile  
  -- Fixed is default setting for new balance account to count per payment method type
  -- Fixed setting can_withdraw and is_default_withdrawal flag for balance account, now based on payment method flag
  
  DECLARE curAccountReference, curCardHolderName VARCHAR(80) DEFAULT NULL;
  DECLARE curIsActive, curFraudCheckable, curKycChecked TINYINT(1) DEFAULT NULL;
  DECLARE kycRequiredPerPlayerAccount, playerDetailIsKycChecked, isSubMethod, isNew, 
	allowDefaultAccount, isDefault, notificationEnabled, withdrawalWithoutDeposit TINYINT(1) DEFAULT 0;
  DECLARE clientID, clientStatIDCheck, paymentMethodIDCheck, parentPaymentMethodID, curPaymentMethodID BIGINT DEFAULT -1;
  DECLARE subPaymentMethodID, paymentGatewayID BIGINT DEFAULT NULL;
  DECLARE auditLogGroupId BIGINT DEFAULT -1; 
  DECLARE curExpiryDate DATE DEFAULT NULL;
  DECLARE notificationTypeID BIGINT;
  DECLARE v_is_default_withdrawal, paymentMethodCanWithdraw, canWithdrawWithoutdeposit, hasCRN TINYINT(1) DEFAULT 0;
  DECLARE crnCheckSum integer DEFAULT 0;
  DECLARE paymentMethodIsActive TINYINT(1) DEFAULT 1;
  DECLARE clientIsActive TINYINT(1) DEFAULT 1;
  DECLARE clientAccountIsClosed TINYINT(1) DEFAULT 1;

  SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id, gaming_clients.is_kyc_checked, gaming_clients.account_activated, gaming_clients.is_account_closed
  INTO clientStatIDCheck, clientID, playerDetailIsKycChecked, clientIsActive, clientAccountIsClosed
  FROM gaming_client_stats
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  JOIN gaming_clients ON 
    gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 AND
    gaming_client_stats.client_id=gaming_clients.client_id 
  WHERE gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL);
  IF (clientStatIDCheck-1) THEN 
    SET statusCode=1;
  END IF;

  IF (clientAccountIsClosed = 1) THEN
 	SET statusCode=1;
	LEAVE root;
  END IF;

  IF (balanceAccountID IS NOT NULL AND (paymentMethodID IS NULL OR paymentMethodID=0)) THEN
	SELECT payment_method_id, sub_payment_method_id 
    INTO paymentMethodID, subPaymentMethodID 
    FROM gaming_balance_accounts WHERE balance_account_id=balanceAccountID;
    SET allowDefaultAccount=0;
  ELSE

	  SELECT payment_method_id, parent_payment_method_id, is_sub_method, allow_default_account, can_withdraw, can_withdraw_without_payment_account 
	  INTO paymentMethodIDCheck, parentPaymentMethodID, isSubMethod, allowDefaultAccount, paymentMethodCanWithdraw, canWithdrawWithoutdeposit
	  FROM gaming_payment_method
	  WHERE payment_method_id=paymentMethodID;

	  IF (paymentMethodIDCheck=-1) THEN
		SET statusCode=2;
		LEAVE root;
	  END IF;

	  IF (isSubMethod=1) THEN
		SET subPaymentMethodID=paymentMethodID;
		SET paymentMethodID=IFNULL(parentPaymentMethodID, paymentMethodID);
	  ELSE
		SET subPaymentMethodID=paymentMethodID;
	  END IF;

  END IF;

  SELECT is_active INTO paymentMethodIsActive FROM gaming_payment_method gpm WHERE gpm.payment_method_id = paymentMethodID;

  IF (paymentMethodIsActive != 1) THEN
 	SET statusCode=4;
	LEAVE root;
  END IF;


  IF (balanceAccountID IS NULL) THEN 
  
	  IF (paymentGateway IS NULL AND getGatewayFromPaymentMethodProfile=0) THEN
		SET paymentGateway = 'Internal';
	  END IF;

	  IF (paymentGateway IS NOT NULL) THEN
		SELECT payment_gateway_id, withdrawal_without_deposit INTO paymentGatewayID, withdrawalWithoutDeposit FROM gaming_payment_gateways WHERE name=paymentGateway;
	  END IF;

      SELECT balance_account_id INTO balanceAccountID
	  FROM gaming_balance_accounts
	  WHERE client_stat_id=clientStatID AND payment_method_id=paymentMethodID 
	  AND (accountReference IS NULL OR account_reference IS NULL OR account_reference=accountReference)																								   
		AND (paymentGatewayID IS NULL OR payment_gateway_id IS NULL OR payment_gateway_id=paymentGatewayID)
	  ORDER BY gaming_balance_accounts.balance_account_id DESC LIMIT 1;
	  
      SET isNew=IF(balanceAccountID IS NULL, 1, 0);

      IF (isNew=0 AND isRetrievalMode=1) THEN
		SET newBalanceAccountID=balanceAccountID;
		LEAVE root;
	  END IF;
  ELSE
  
	IF (paymentGateway IS NOT NULL) THEN
	  SELECT payment_gateway_id INTO paymentGatewayID FROM gaming_payment_gateways WHERE name=paymentGateway;
  END IF;
  
  END IF;
  
  IF (allowDefaultAccount=1) THEN
    SET @numMatch=0;
    SELECT COUNT(balance_account_id) INTO @numMatch FROM gaming_balance_accounts WHERE client_stat_id=clientStatID AND payment_method_id = paymentMethodID;  
    SET isDefault=IF(@numMatch=0 AND isActive, 1, 0);
  ELSE
    SET isDefault=0;
  END IF;
  
  SET subPaymentMethodID = IFNULL(subPaymentMethodID, paymentMethodID);
 
 IF (balanceAccountID IS NULL) THEN
     
    SELECT value_bool INTO kycRequiredPerPlayerAccount FROM gaming_settings WHERE name='TRANSFER_KYC_REQUIRED_PER_PLAYER_ACCOUNT';
    
    SET @balance_account_size = 0;
    SELECT COUNT(balance_account_id) INTO @balance_account_size FROM gaming_balance_accounts WHERE client_stat_id = clientStatID AND can_withdraw = 1;
    SET v_is_default_withdrawal = IF (@balance_account_size = 0 AND isActive AND paymentMethodCanWithdraw = 1, 1, 0);
		  
    INSERT INTO gaming_balance_accounts (account_reference, date_created, date_last_used, client_stat_id, is_active, 
		kyc_checked, fraud_checkable, is_default, payment_method_id, sub_payment_method_id, cc_holder_name, expiry_date, 
        session_id, player_token, payment_gateway_id, can_withdraw, is_default_withdrawal)
    SELECT accountReference, NOW(), NOW(), clientStatID, IFNULL(isActive,1), 
		IFNULL(kycChecked, IF(kycRequiredPerPlayerAccount=1 OR playerDetailIsKycChecked=0, 0, 1)), IFNULL(fraudCheckable,1), isDefault, paymentMethodID, subPaymentMethodID, cardHolderName, expiryDate, 
        sessionID, token, paymentGatewayID, paymentMethodCanWithdraw AND canWithdrawWithoutdeposit, v_is_default_withdrawal;
  
    SET balanceAccountID=LAST_INSERT_ID();
    SET kycChecked=IFNULL(kycChecked, IF(kycRequiredPerPlayerAccount=1 OR playerDetailIsKycChecked=0, 0, 1));

	SELECT COUNT(pgma2.attr_name) INTO hasCRN
                    FROM gaming_payment_method gpm
					STRAIGHT_JOIN payment_methods AS pm ON pm.name=gpm.payment_gateway_method_name AND 
		                ((gpm.sub_name IS NULL AND pm.sub_name IS NULL) OR pm.sub_name=gpm.payment_gateway_method_sub_name)
					STRAIGHT_JOIN payment_profiles AS pp ON pm.payment_profile_id=pp.payment_profile_id
					LEFT JOIN gaming_payment_gateways ON pp.payment_gateway_id=gaming_payment_gateways.payment_gateway_id    
                    LEFT JOIN payment_gateways AS pg ON pg.payment_gateway_id=IFNULL(gaming_payment_gateways.payment_gateway_ref, pp.payment_gateway_id)
					LEFT JOIN payment_gateway_methods AS pgm ON pgm.payment_gateway_id=pg.payment_gateway_id AND pgm.payment_method_id=pm.payment_method_id
                    LEFT JOIN payment_gateway_methods_attributes AS pgma ON pgm.payment_gateway_method_id=pgma.payment_gateway_method_id
                    LEFT JOIN payment_gateway_method_attributes AS pgma2 ON pgma2.attr_name = pgma.attr_name
	WHERE gpm.payment_method_id = paymentMethodID AND pgma.attr_name = 'crn';

	IF (hasCRN) THEN
		SET crnCheckSum = GenerateLuhn(balanceAccountID);
		UPDATE gaming_balance_accounts SET customer_reference_number = CONCAT(balanceAccountID, crnCheckSum) WHERE balance_account_id = balanceAccountID;

		INSERT INTO gaming_balance_account_attributes(balance_account_id, attr_name, attr_value) VALUES (balanceAccountID, 'crn', CONCAT(balanceAccountID, crnCheckSum));
	END IF;
    
    IF (paymentGateway IS NULL OR withdrawalWithoutDeposit=1 OR getGatewayFromPaymentMethodProfile) THEN
	  CALL PaymentCreateDummyPurchaseForWithdrawal(balanceAccountID, UUID(), @dummyStatusCode);
	END IF;
  ELSE

    SELECT account_reference, is_active, kyc_checked, fraud_checkable, payment_method_id, expiry_date, cc_holder_name 
    INTO curAccountReference, curIsActive, curKycChecked, curFraudCheckable, curPaymentMethodID, curExpiryDate, curCardHolderName
	FROM gaming_balance_accounts WHERE balance_account_id=balanceAccountID;

    UPDATE gaming_balance_accounts 
    SET account_reference=IFNULL(accountReference, account_reference), is_active=IFNULL(isActive, is_active), kyc_checked=IFNULL(kycChecked, kyc_checked), fraud_checkable=IFNULL(fraudCheckable, fraud_checkable), 
        payment_method_id=IFNULL(paymentMethodID, payment_method_id), sub_payment_method_id=IF(subPaymentMethodID=paymentMethodID, sub_payment_method_id, subPaymentMethodID), cc_holder_name=IFNULL(cardHolderName,cc_holder_name), 
        expiry_date=IFNULL(expiryDate,expiry_date), is_default = IF(isActive = 0, IFNULL(isInternal,0), IFNULL(isDefaultWithdrawal,is_default)), is_default_withdrawal = IFNULL(isDefaultWithdrawal,IF(isActive = 0, 0, is_default_withdrawal)), player_token=IFNULL(token, player_token), 
        payment_gateway_id=IFNULL(paymentGatewayID,payment_gateway_id), session_id=IFNULL(sessionID,-1), is_internal = IFNULL(isInternal,is_internal), can_withdraw = IFNULL(canWithdraw,can_withdraw)
    WHERE balance_account_id=balanceAccountID;
	
  END IF;
 
  SET notificationTypeID = IF (isNew = 1, 522, 521);
  CALL NotificationEventCreate(notificationTypeID,clientStatIDCheck, balanceAccountID, 0);        

  -- Add to audit trail
  INSERT INTO gaming_balance_account_changes (balance_account_id, is_active, kyc_checked, fraud_checkable, expiry_date, user_id, session_id, timestamp, account_reference, cardholder_name)
  VALUES (balanceAccountID, isActive, kycChecked, fraudCheckable, expiryDate, userID, IFNULL(sessionID,-1), NOW(), accountReference, cardHolderName); 

	-- New version of audit logs

    SET auditLogGroupId = AuditLogNewGroup(userID, sessionID, balanceAccountID, 3, IFNULL(modifierEntityType, IF(userID=0, 'System', 'User')), NULL, NULL, clientID);
 
	IF (accountReference IS NOT NULL) THEN
		IF (curAccountReference IS NULL OR accountReference!=curAccountReference) THEN
			CALL AuditLogAttributeChange('Account Reference', balanceAccountID, auditLogGroupId, accountReference, curAccountReference, NOW());
		END IF;
	END IF;
	
	IF (isActive IS NOT NULL) THEN
		IF (curIsActive IS NULL OR isActive!=curIsActive) THEN
			CALL AuditLogAttributeChange('Is Active', balanceAccountID, auditLogGroupId, CASE isActive WHEN 1 THEN 'YES' ELSE 'NO' END, CASE WHEN isNew THEN NULL WHEN curIsActive=1 THEN 'YES' ELSE 'NO' END, NOW());
		END IF;
	END IF;

	IF (kycChecked IS NOT NULL) THEN
		IF (curKycChecked IS NULL OR kycChecked!=curKycChecked) THEN
			CALL AuditLogAttributeChange('KYC Checked', balanceAccountID, auditLogGroupId, CASE kycChecked WHEN 1 THEN 'YES' ELSE 'NO' END, CASE WHEN isNew THEN NULL WHEN curKycChecked=1 THEN 'YES' ELSE 'NO' END, NOW());
		END IF;
	END IF;

	IF (fraudCheckable IS NOT NULL) THEN
		IF (curFraudCheckable IS NULL OR fraudCheckable!=curFraudCheckable) THEN 
			CALL AuditLogAttributeChange('Fraud Checkable', balanceAccountID, auditLogGroupId, CASE fraudCheckable WHEN 1 THEN 'YES' ELSE 'NO' END, CASE WHEN isNew THEN NULL WHEN curFraudCheckable=1 THEN 'YES' ELSE 'NO' END, NOW());
		END IF;
	END IF; 

	IF (expiryDate IS NOT NULL) THEN
		IF (curExpiryDate IS NULL OR expiryDate!=curExpiryDate) THEN
			CALL AuditLogAttributeChange('Expiry Date', balanceAccountID, auditLogGroupId, expiryDate, curExpiryDate, NOW());
		END IF;
	END IF;

	IF (cardHolderName IS NOT NULL) THEN
		IF (curCardHolderName IS NULL OR cardHolderName!=curCardHolderName) THEN
			CALL AuditLogAttributeChange('Account Holder', balanceAccountID, auditLogGroupId, cardHolderName, curCardHolderName, NOW());
		END IF;
	END IF;

	IF isNew THEN
		CALL AuditLogAttributeChange('Is Default Withdrawal', balanceAccountID, auditLogGroupId, CASE v_is_default_withdrawal WHEN 1 THEN 'YES' ELSE 'NO' END, NULL, NOW());
	END IF; 

  IF (isRetrievalMode=0) THEN  
     SELECT balanceAccountID AS balance_account_id;
  END IF;

  SET newBalanceAccountID=balanceAccountID;
  SET statusCode=0;
  
END root$$

DELIMITER ;

