DROP procedure IF EXISTS `BonusReverseLostBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusReverseLostBonus`(clientStatID BIGINT, bonusInstanceID BIGINT, expiryDate DATETIME, OUT statusCode INT)
root: BEGIN
  
  
  
  DECLARE clientStatIDCheck, bonusInstanceIDCheck BIGINT DEFAULT -1;
  DECLARE bonusAmount, bonusWinLockedAmount DECIMAL(18, 5) DEFAULT 0;
  DECLARE expiryDateCur DATETIME DEFAULT NULL;
  
  
  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  IF (clientStatIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT bonus_instance_id, expiry_date INTO bonusInstanceIDCheck, expiryDateCur 
  FROM gaming_bonus_instances WHERE bonus_instance_id=bonusInstanceID AND client_stat_id=clientStatID AND is_active=0 AND is_lost=1 AND is_used_all=0;
  
  IF (bonusInstanceIDCheck=-1) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  IF (expiryDate IS NOT NULL) THEN
	UPDATE gaming_bonus_instances SET expiry_date=expiryDate WHERE bonus_instance_id=bonusInstanceID AND client_stat_id=clientStatID;	
	SET expiryDateCur=expiryDate;
  END IF;
  
  IF (expiryDateCur < NOW()) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  
  SET bonusInstanceIDCheck=-1;
  SELECT bonus_instance_id, ROUND(SUM(bonus_amount),0), ROUND(SUM(bonus_win_locked_amount),0) 
  INTO bonusInstanceIDCheck, bonusAmount, bonusWinLockedAmount
  FROM gaming_bonus_losts WHERE bonus_instance_id=bonusInstanceID AND is_reversed=0
  GROUP BY bonus_instance_id;
  
  IF (bonusInstanceIDCheck=-1 OR (bonusAmount+bonusWinLockedAmount)<=0) THEN
    SET statusCode=4;
    LEAVE root;
  END IF;
  
  
  UPDATE gaming_bonus_losts SET is_reversed=1 WHERE bonus_instance_id=bonusInstanceID;
  
  UPDATE gaming_bonus_instances
  SET bonus_amount_remaining=bonusAmount, current_win_locked_amount=bonusWinLockedAmount, lost_date=NULL, is_lost=0, is_active=1
  WHERE bonus_instance_id=bonusInstanceID;
  
  
  UPDATE gaming_client_stats 
  SET 
    gaming_client_stats.current_bonus_balance=gaming_client_stats.current_bonus_balance+bonusAmount,
    gaming_client_stats.current_bonus_win_locked_balance=gaming_client_stats.current_bonus_win_locked_balance+bonusWinLockedAmount
  WHERE gaming_client_stats.client_stat_id=clientStatID;  
  
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, pending_bet_real, pending_bet_bonus,withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, ROUND(bonusAmount+bonusWinLockedAmount,0), ROUND((bonusAmount+bonusWinLockedAmount)/gaming_operator_currency.exchange_rate, 5), gaming_client_stats.currency_id, gaming_operator_currency.exchange_rate, 0, bonusAmount, bonusWinLockedAmount, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, gaming_bonus_instances.bonus_instance_id , pending_bets_real, pending_bets_bonus,withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_bonus_instances  
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BonusLostReversed'
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=gaming_bonus_instances.client_stat_id 
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  WHERE gaming_bonus_instances.bonus_instance_id=bonusInstanceID; 
 
  SET @transactionID=LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,amount_free_bet, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points,loyalty_points_after,loyalty_points_bonus,loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus,  IF(is_free_bonus = 1 OR gaming_bonus_types_awarding.name = 'FreeBet',amount_bonus,0), amount_bonus_win_locked, timestamp, gaming_transactions.client_id, gaming_transactions.client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,gaming_transactions.loyalty_points,gaming_transactions.loyalty_points_after,gaming_transactions.loyalty_points_bonus,gaming_transactions.loyalty_points_after_bonus  
  FROM gaming_transactions
		STRAIGHT_JOIN gaming_bonus_instances ON gaming_bonus_instances.bonus_instance_id =  gaming_transactions.extra_id
		STRAIGHT_JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
  WHERE transaction_id=@transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID,LAST_INSERT_ID());  
 
  SET statusCode=0;
END root$$

DELIMITER ;

