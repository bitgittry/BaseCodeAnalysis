DROP procedure IF EXISTS `TransactionBalanceAccountSetDefault`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionBalanceAccountSetDefault`(balanceAccountID BIGINT, sessionID BIGINT, OUT statusCode INT)
root:BEGIN
  -- First Version
  -- The default should be by payment method

  DECLARE allowDefaultAccount, isActive TINYINT(1) DEFAULT 0;
  DECLARE balanceAccountIDCheck, clientStatID, paymentMethodID BIGINT DEFAULT -1;
  
  SELECT balance_account_id, client_stat_id, gaming_balance_accounts.is_active, gaming_payment_method.payment_method_id, gaming_payment_method.allow_default_account
  INTO balanceAccountIDCheck, clientStatID, isActive, paymentMethodID, allowDefaultAccount
  FROM gaming_balance_accounts
  JOIN gaming_payment_method ON gaming_balance_accounts.balance_account_id=balanceAccountID AND gaming_balance_accounts.payment_method_id=gaming_payment_method.payment_method_id;

  IF (balanceAccountIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  IF (allowDefaultAccount=0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  IF (isActive = 0) THEN
    SET statusCode = 3;
    LEAVE root; 
  END IF;

  UPDATE gaming_balance_accounts
  SET is_default=0, session_id=sessionID
  WHERE client_stat_id=clientStatID AND is_default=1 AND payment_method_id=paymentMethodID;
  
  UPDATE gaming_balance_accounts
  SET is_default=1, session_id=sessionID
  WHERE balance_account_id=balanceAccountID;

  SET statusCode=0;
END root$$

DELIMITER ;

