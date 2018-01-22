DROP procedure IF EXISTS `TransactionAdjustRedeemLoyaltyPoints`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TransactionAdjustRedeemLoyaltyPoints`(sessionID BIGINT, clientStatID BIGINT, varAmount DECIMAL(18, 5), varLoyaltyPoints DECIMAL(18, 5), platformType VARCHAR(80), OUT statusCode INT)
root: BEGIN
  
  DECLARE currentRealBalance, exchangeRate, currentLoyaltyPoints DECIMAL(18, 5) DEFAULT 0;
  DECLARE clientStatIDCheck, transactionID, currencyID BIGINT DEFAULT -1;
  DECLARE platformTypeID TINYINT(4) DEFAULT -1;

  SET @sessionID = sessionID;
  SET @clientStatID = clientStatID;
  SET @varAmount = varAmount;
  SET @varLoyaltyPoints = varLoyaltyPoints;    
  SET @statusCode = statusCode;    
  
  
  SELECT 	client_stat_id, current_real_balance, current_loyalty_points, currency_id 
  INTO 		clientStatIDCheck, currentRealBalance, currentLoyaltyPoints, currencyID
  FROM 		gaming_client_stats
  WHERE 	client_stat_id = @clientStatID and is_active=1;  
  
  
  SELECT 	exchange_rate INTO exchangeRate
  FROM 		gaming_operator_currency 
  JOIN 		gaming_operators 
				ON gaming_operators.is_main_operator 
				AND gaming_operator_currency.operator_id = gaming_operators.operator_id
  WHERE 	gaming_operator_currency.currency_id = currencyID;
  
  
  IF (clientStatIDCheck = -1) THEN
    SET statusCode = 1;
    LEAVE root;
  END IF;  
  
  
  IF (@varAmount < 0 OR currentRealBalance + @varAmount < 0) THEN
    SET statusCode = 2;
    LEAVE root;
  END IF; 

  
  IF (@varLoyaltyPoints > 0 AND currentLoyaltyPoints - @varLoyaltyPoints < 0) THEN
    SET statusCode = 3;  
    LEAVE root;
  END IF; 
  
  	IF (platformType IS NOT NULL) THEN
		SELECT platform_type_id INTO platformTypeID
		FROM gaming_platform_types
		WHERE platform_type = platformType;
    END IF;

  UPDATE 		gaming_client_stats  
  SET 			current_real_balance = ROUND(current_real_balance + @varAmount, 0), 
				total_adjustments = ROUND(total_adjustments + @varAmount, 0), 
				total_adjustments_base = total_adjustments_base + ROUND(@varAmount/exchangeRate, 5),
				current_loyalty_points = ROUND(current_loyalty_points - @varLoyaltyPoints, 0) , 
				total_loyalty_points_used = total_loyalty_points_used + @varLoyaltyPoints
  WHERE 		client_stat_id = @clientStatID;
  
  INSERT INTO 	gaming_transactions
				(payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, 
				 amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, 
				 client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after,  
				 loyalty_points_after, extra_id, session_id, reason, pending_bet_real, 
				 pending_bet_bonus, withdrawal_pending_after, platform_type_id) 

  SELECT 	  	gaming_payment_transaction_type.payment_transaction_type_id, @varAmount, ROUND(@varAmount/exchangeRate,5), gaming_client_stats.currency_id, exchangeRate, 
				@varAmount, 0, 0, -@varLoyaltyPoints, NOW(), 
				gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, 
				current_loyalty_points, sessionID, sessionID, 'Loyalty Points Redemption', pending_bets_real, 
				pending_bets_bonus, withdrawal_pending_amount, IF(platformTypeID=-1,NULL,platformTypeID)
  FROM 		  	gaming_client_stats 
				JOIN gaming_payment_transaction_type 
					ON gaming_payment_transaction_type.name = 'LoyaltyPointsRedemption'
  WHERE 		gaming_client_stats.client_stat_id = @clientStatID;  
 
  
  IF (ROW_COUNT() = 0) THEN
    SET statusCode = 4;
    LEAVE root;
  END IF;
  
  SET @transactionID = LAST_INSERT_ID();
  
  INSERT INTO 	gaming_game_plays 
				(amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, 
				 amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, 
				 balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, currency_id, session_id, 
				 transaction_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, platform_type_id) 

  SELECT 		amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, 
				amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, 
				balance_real_after, balance_bonus_after + balance_bonus_win_locked_after, balance_bonus_win_locked_after, currency_id, session_id, 
				gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus,loyalty_points, loyalty_points_after, platform_type_id
  FROM 			gaming_transactions
  WHERE 		transaction_id = @transactionID;

  INSERT INTO 	gaming_loyalty_redemption_transactions 
				(loyalty_redemption_id, loyalty_redemption_prize_type_id, extra_id, loyalty_points, amount, 
				 free_rounds, transaction_date, limited_offer_placing, client_stat_id, currency_id, 
			     session_id)
  SELECT 		0, 2, 0, 0, ABS(loyalty_points), 
				0, timestamp, 0, client_stat_id, currency_id,
				session_id
  FROM 			gaming_transactions
  WHERE 		transaction_id = @transactionID;
  
  SELECT 		transaction_id, gaming_payment_transaction_type.payment_transaction_type_id AS transaction_type_id, gaming_payment_transaction_type.name AS transaction_type_name, 
				gaming_transactions.amount_total, gaming_transactions.amount_total_base, gaming_transactions.amount_real, gaming_transactions.amount_bonus, gaming_transactions.amount_bonus_win_locked, amount_cashback, loyalty_points, 
				gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, gaming_transactions.reason,
				gaming_currency.currency_code, gaming_transactions.balance_history_id
  FROM 			gaming_transactions
				JOIN gaming_payment_transaction_type 
					ON gaming_transactions.payment_transaction_type_id = gaming_payment_transaction_type.payment_transaction_type_id
				JOIN gaming_currency 
					ON gaming_transactions.currency_id = gaming_currency.currency_id
  WHERE 		gaming_transactions.transaction_id = @transactionID;
  
  SET statusCode = 0;
END root$$

DELIMITER ;