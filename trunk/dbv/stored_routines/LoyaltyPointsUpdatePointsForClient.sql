DROP procedure IF EXISTS `LoyaltyPointsUpdatePointsForClient`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `LoyaltyPointsUpdatePointsForClient`(sessionID BIGINT, clientID BIGINT, loyaltyPointsAmount DECIMAL(18,5), 
 RuleInstanceID BIGINT, PrizeID BIGINT, UserID BIGINT, Reason VARCHAR(512), platformType VARCHAR(80), OUT statusCode INT)
root:BEGIN
  -- Added UserID and Reason
  -- Added Automatic VIP Level Progression by proc: PlayerUpdateVIPLevel

  DECLARE totalLoyaltyPoints INT DEFAULT 0;
  DECLARE ClientIDTemp, clientStatID, transactionID, loyaltyPointsTxnID BIGINT DEFAULT 0;
  DECLARE currentLoyaltyPoints DECIMAL (18,5) DEFAULT 0; 
  DECLARE platformTypeID TINYINT(4) DEFAULT -1;

  SET statusCode = 0;
  
  SELECT client_id, client_stat_id, current_loyalty_points 
  INTO ClientIDTemp, clientStatID, currentLoyaltyPoints 
  FROM gaming_client_stats WHERE client_id=clientID AND is_active=1 LIMIT 1 
  FOR UPDATE;

  IF ClientIDTemp=0 THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

 IF (platformType IS NOT NULL) THEN
		SELECT platform_type_id INTO platformTypeID
		FROM gaming_platform_types
		WHERE platform_type = platformType;
  END IF;
  
  IF loyaltyPointsAmount >= 0 THEN
    UPDATE gaming_client_stats 
    SET total_loyalty_points_given = total_loyalty_points_given + loyaltyPointsAmount, current_loyalty_points = current_loyalty_points + loyaltyPointsAmount
    WHERE client_id = clientID AND is_active=1;
  ELSE
	IF (currentLoyaltyPoints<ABS(loyaltyPointsAmount)) THEN
		SET statusCode=2;
		LEAVE root;
	END IF;
	-- loyaltyPointsAmount is a negative value
    UPDATE gaming_client_stats 
    SET total_loyalty_points_used = total_loyalty_points_used - loyaltyPointsAmount, current_loyalty_points = current_loyalty_points + loyaltyPointsAmount
    WHERE client_id = clientID AND is_active=1;
  END IF;

  INSERT INTO gaming_clients_loyalty_points_transactions (client_id, time_stamp, amount, amount_total, rule_instance_id, prize_id, user_id, reason)
  SELECT clientID, NOW(), loyaltyPointsAmount, current_loyalty_points, RuleInstanceID, PrizeID, UserID, Reason
  FROM gaming_client_stats 
  WHERE client_stat_id=clientStatID;
  
  SET loyaltyPointsTxnID = LAST_INSERT_ID();
  
  -- Gaming Transactions
  INSERT INTO gaming_transactions
	(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, 
	 amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, 
	 client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after,  
	 loyalty_points_after, extra_id, session_id, reason, pending_bet_real, 
	 pending_bet_bonus, withdrawal_pending_after,loyalty_points_bonus,loyalty_points_after_bonus, platform_type_id) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, 0, 0, gaming_client_stats.currency_id, 0, 
	0, 0, 0, loyaltyPointsAmount, NOW(), 
	gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, 
	current_loyalty_points, loyaltyPointsTxnID, sessionID, Reason, pending_bets_real, 
	pending_bets_bonus, withdrawal_pending_amount,0,(gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`), IF(platformTypeID=-1,NULL,platformTypeID)
  FROM gaming_client_stats 
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name = 'LoyaltyPoints'
  WHERE gaming_client_stats.client_stat_id = clientStatID;  

  -- Gaming Game Plays
  SET transactionID = LAST_INSERT_ID();
  
  INSERT INTO gaming_game_plays 
	(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, 
	 amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, 
	 balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, extra_id,
	 transaction_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, platform_type_id) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, 
	amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, 
	balance_real_after, balance_bonus_after + balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, extra_id,
	gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, platform_type_id
  FROM gaming_transactions
  WHERE transaction_id = transactionID;

  CALL GameUpdateRingFencedBalances(clientStatID, LAST_INSERT_ID());  
  
  IF (loyaltyPointsAmount>0) THEN
     CALL PlayerUpdateVIPLevel(clientStatID,0);
  END IF;

END root$$

DELIMITER ;

