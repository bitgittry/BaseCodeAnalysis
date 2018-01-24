DROP procedure IF EXISTS `TransactionCheckCanWithdraw`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionCheckCanWithdraw`(sessionID BIGINT, clientStatID BIGINT, balanceAccountID BIGINT, varAmount DECIMAL(18, 5), skipTransactionLimitCheck TINYINT(1), OUT statusCode INT)
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
*/
  
  DECLARE operatorID, balanceHistoryID, clientStatIDCheck, clientID, clientIDCheck, currencyID, currencyIDCheck, 
	clientSegmentID, balanceAccountIDCheck, paymentMethodID, paymentMethodSubID, paymentMethodGroupID, 
    numRestrictions BIGINT DEFAULT -1;

  DECLARE currentRealBalance, exchangeRate, totalPaymentDeposits, finalMaximumammount, totalRealWon, 
	totalBonusTransferred, totalBonusWinLockedTransferred, withdrawnAmount, withdrawalPendingAmount, maxAllowedWithdrawals, deferredTax DECIMAL(18, 5) DEFAULT 0;

  DECLARE isSuspicious, isTestPlayer, testPlayerAllowTransfers, isWaitingKYC, autoProcessWithdrawals, 
	requireClientInfo, isValidated, isDisabled, isCountryDisabled, fraudEnabled, fraudOnDepositEnabled, dissallowTransfer, 
    playerRestrictionEnabled, balanceAccountActiveFlag, disableSaveAccountBalance, withdrawalAllowed, 
    restrictWithdrawalsToOnlyWinnings, kycReturnError, taxEnabled TINYINT(1) DEFAULT 0;

  DECLARE checkWithdrawLimitReturn, errorCode, hasFraudRows INT DEFAULT 0;
  DECLARE paymentMethodName, accountReference, uniqueTransactionIDLast, paymentGatewayName VARCHAR(80) DEFAULT NULL;
  DECLARE paymentGroupDepositAllowed TINYINT(1) DEFAULT 1;
  
  SET statusCode=0;
  
  SELECT client_stat_id, gaming_clients.client_id, is_suspicious, withdrawal_allowed, is_test_player, test_player_allow_transfers, 
	client_segment_id, current_real_balance, gaming_client_stats.currency_id, 
    total_real_won, total_bonus_transferred, total_bonus_win_locked_transferred, withdrawn_amount, withdrawal_pending_amount, deferred_tax
  INTO clientStatIDCheck, clientID, isSuspicious, withdrawalAllowed, isTestPlayer, testPlayerAllowTransfers, 
	clientSegmentID, currentRealBalance, currencyID, totalRealWon, totalBonusTransferred, totalBonusWinLockedTransferred, withdrawnAmount, withdrawalPendingAmount, deferredTax
  FROM gaming_client_stats 
  LEFT JOIN gaming_fraud_rule_client_settings ON gaming_fraud_rule_client_settings.client_id = gaming_client_stats.client_id
  JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
  WHERE gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.is_active=1 AND (gaming_clients.is_account_closed=0 AND (gaming_fraud_rule_client_settings.block_account = 0 OR gaming_fraud_rule_client_settings.block_account = NULL));
  
  
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
    IF (currentRealBalance<varAmount) THEN
      SET statusCode=3;
    END IF;
  END IF;
  
	SELECT value_bool INTO taxEnabled FROM gaming_settings WHERE name='TAX_ON_GAMEPLAY_ENABLED';
    IF(taxEnabled = 1 and deferredTax > 0) THEN
		IF((currentRealBalance - deferredTax) < varAmount) THEN
			SET statusCode=16;
		END IF;
	END IF;
  
	IF (statusCode=0) THEN
		IF (CalculateWithdrawableAmount(clientStatID)<varAmount) THEN
		  SET statusCode=14;
		END IF;
	END IF;
  

  
  IF (statusCode=0) THEN
    SELECT balance_account_id, gaming_payment_method.payment_method_id,  subpayment.payment_method_group_id, gaming_payment_method.name, 
		subpayment.payment_method_id, gaming_balance_accounts.is_active, account_reference, unique_transaction_id_last
    INTO balanceAccountIDCheck, paymentMethodID,  paymentMethodGroupID, paymentMethodName, paymentMethodSubID, balanceAccountActiveFlag, accountReference, uniqueTransactionIDLast
    FROM gaming_balance_accounts
    JOIN gaming_client_stats ON gaming_balance_accounts.client_stat_id=gaming_client_stats.client_stat_id
    JOIN gaming_payment_method ON gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id
	JOIN gaming_payment_method subpayment ON gaming_balance_accounts.sub_payment_method_id=subpayment.payment_method_id
    WHERE gaming_balance_accounts.balance_account_id=balanceAccountID;
    
    IF (balanceAccountIDCheck=-1) THEN
      SET statusCode=4;
    ELSEIF (balanceAccountActiveFlag=0) THEN
      SET statusCode=4;
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
    SELECT value_bool INTO fraudEnabled FROM gaming_settings WHERE name='FRAUD_ENABLED';
    SELECT value_bool INTO fraudOnDepositEnabled FROM gaming_settings WHERE name='FRAUD_ON_DEPOSIT_ENABLED';
    IF (fraudEnabled=1 AND fraudOnDepositEnabled=1) THEN
      SET clientIDCheck=-1;
      SET dissallowTransfer=0;
	  SET paymentGroupDepositAllowed=1;
      SELECT client_id, disallow_transfers, IFNULL(withdrawal_allowed,1), COUNT(*)
      INTO clientIDCheck, dissallowTransfer, paymentGroupDepositAllowed, hasFraudRows
      FROM gaming_fraud_client_events AS cl_events
      JOIN gaming_fraud_classification_types ON 
        cl_events.client_id=clientID AND cl_events.is_current=1 AND
        cl_events.fraud_classification_type_id=gaming_fraud_classification_types.fraud_classification_type_id
      LEFT JOIN gaming_fraud_classification_payment_groups gfcpg ON 
		gaming_fraud_classification_types.fraud_classification_type_id = gfcpg.fraud_classification_type_id AND gfcpg.payment_method_group_id = paymentMethodGroupID;
      
	  IF (hasFraudRows > 0 AND (clientIDCheck=-1 OR dissallowTransfer OR paymentGroupDepositAllowed = 0)) THEN
        SET statusCode=12;
      END IF;
    END IF;
  END IF;
  
  
  IF (statusCode=0) THEN
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
  
  
  IF (statusCode=0 AND isTestPlayer=0 AND skipTransactionLimitCheck = 0) THEN
    SET checkWithdrawLimitReturn = (SELECT TransactionCheckWithdrawAmountWithinLimit(clientStatID, paymentMethodSubID, varAmount, balanceAccountID)); 
    
    IF (checkWithdrawLimitReturn = 0 AND paymentMethodSubID!=paymentMethodID) THEN
		SET checkWithdrawLimitReturn = (SELECT TransactionCheckWithdrawAmountWithinLimit(clientStatID, paymentMethodID, varAmount, balanceAccountID)); 
    END IF;  
    
    IF (checkWithdrawLimitReturn=4) THEN
	
	  SELECT value_bool INTO kycReturnError FROM gaming_settings WHERE name='TRANSFER_KYC_REQUIRED_RETURN_ERROR_ON_WITHDRAWAL'; 
      
      IF (kycReturnError=0) THEN
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

END$$

DELIMITER ;

