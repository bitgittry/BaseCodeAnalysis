DROP procedure IF EXISTS `TransactionBalanceAccountSetDefaultWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionBalanceAccountSetDefaultWithdrawal`(balanceAccountID BIGINT, sessionID BIGINT, modifierEntityType VARCHAR(45), OUT statusCode INT)
root:BEGIN
   -- added check of withdrawal

  DECLARE v_balanceAccountID, v_clientStatID, v_clientID, userID, paymentMethodID BIGINT;
  DECLARE v_isActive, canWithdraw TINYINT(1);

  SELECT gaming_balance_accounts.balance_account_id, gaming_balance_accounts.client_stat_id, gaming_balance_accounts.is_active,  gaming_client_stats.client_id, gaming_balance_accounts.payment_method_id
		INTO v_balanceAccountID, v_clientStatID, v_isActive , v_clientID, paymentMethodID
	FROM gaming_balance_accounts 
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_balance_accounts.client_stat_id
	WHERE balance_account_id = balanceAccountID;
  
  IF (v_balanceAccountID is null) THEN
    SET statusCode = 564;
    LEAVE root; 
  END IF;

  IF (v_isActive = 0) THEN
    SET statusCode = 926;
    LEAVE root; 
  END IF;

  -- check if payment method allows withdrawals
  SELECT can_withdraw INTO canWithdraw
  FROM gaming_payment_method
  WHERE payment_method_id = paymentMethodID;

  IF(IFNULL(canWithdraw,1) = 0) THEN
	SET statusCode = 1;
    LEAVE root; 
  END IF;

  SELECT user_id INTO userID FROM sessions_main WHERE session_id = sessionID;
  -- Audit log for the account being default withdrawal 
  SELECT AuditLogAttributeChangeFunc('Is Default Withdrawal', balance_account_id, AuditLogNewGroup(userID, sessionID, balance_account_id, 3, modifierEntityType, NULL, NULL, v_clientID),'NO', 'YES', NOW()) 
	FROM gaming_balance_accounts WHERE client_stat_id = v_clientStatID and is_default_withdrawal = 1;
  -- Audit log for the account being set as default withdrawal
  SELECT AuditLogAttributeChangeFunc('Is Default Withdrawal', balance_account_id, AuditLogNewGroup(userID, sessionID, balance_account_id, 3, modifierEntityType, NULL, NULL, v_clientID),'YES', 'NO', NOW()) 
	FROM gaming_balance_accounts WHERE client_stat_id = v_clientStatID and balance_account_id = balanceAccountID;

  UPDATE gaming_balance_accounts SET is_default_withdrawal = 0, session_id = sessionID WHERE client_stat_id = v_clientStatID and is_default_withdrawal = 1;
  
  UPDATE gaming_balance_accounts SET is_default_withdrawal = 1, session_id = sessionID WHERE client_stat_id = v_clientStatID and balance_account_id = balanceAccountID;

  SET statusCode = 0;
END root$$

DELIMITER ;

