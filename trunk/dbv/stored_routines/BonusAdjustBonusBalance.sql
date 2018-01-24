DROP procedure IF EXISTS `BonusAdjustBonusBalance`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusAdjustBonusBalance`(clientStatID BIGINT)
BEGIN
  
  SET @clientStatID=clientStatID;
  
  INSERT INTO gaming_bonus_adjustment_counter(date_created) VALUES (NOW());
  SET @bonusAdjustmentCounterID=LAST_INSERT_ID();
  
  INSERT INTO gaming_bonus_adjustment_counter_clients(bonus_adjustment_counter_id, client_stat_id, bonus_amount, bonus_win_locked_amount)
  SELECT @bonusAdjustmentCounterID, client_stat_id, current_bonus_balance-bonus_amount_remaining, current_bonus_win_locked_balance-current_win_locked_amount
  FROM
  (
    SELECT gaming_client_stats.client_stat_id, current_bonus_balance, current_bonus_win_locked_balance, IFNULL(bonus_amount_remaining,0) AS bonus_amount_remaining, IFNULL(current_win_locked_amount,0) AS current_win_locked_amount
    FROM gaming_client_stats 
    LEFT JOIN
    (
      SELECT client_stat_id, SUM(bonus_amount_remaining) AS bonus_amount_remaining, SUM(current_win_locked_amount) AS current_win_locked_amount
      FROM gaming_bonus_instances
      WHERE (@clientStatID=0 OR client_stat_id=@clientStatID) AND is_active=1
      GROUP BY client_stat_id
    ) AS PB ON gaming_client_stats.client_stat_id=PB.client_stat_id
    WHERE (@clientStatID=0 OR gaming_client_stats.client_stat_id=@clientStatID)
  ) AS XX
  WHERE current_bonus_balance!=bonus_amount_remaining OR current_bonus_win_locked_balance!=current_win_locked_amount;
  
  UPDATE gaming_client_stats  
  JOIN gaming_bonus_adjustment_counter_clients AS bonus_adjustments ON 
    bonus_adjustments.bonus_adjustment_counter_id=@bonusAdjustmentCounterID AND 
    gaming_client_stats.client_stat_id=bonus_adjustments.client_stat_id
  SET current_bonus_balance=current_bonus_balance-bonus_adjustments.bonus_amount, current_bonus_win_locked_balance=current_bonus_win_locked_balance-bonus_adjustments.bonus_win_locked_amount;
  
  INSERT INTO gaming_transactions
  (payment_transaction_type_id, amount_total, amount_total_base, currency_id, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, loyalty_points, timestamp, client_id, client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, loyalty_points_after, extra_id, reason, pending_bet_real, pending_bet_bonus,withdrawal_pending_after, loyalty_points_bonus, loyalty_points_after_bonus) 
  SELECT gaming_payment_transaction_type.payment_transaction_type_id, ROUND(bonus_amount+bonus_win_locked_amount,0), ROUND((bonus_amount+bonus_win_locked_amount)/gaming_operator_currency.exchange_rate,5), gaming_client_stats.currency_id, gaming_operator_currency.exchange_rate, 0, bonus_amount, bonus_win_locked_amount, 0, NOW(), gaming_client_stats.client_id, gaming_client_stats.client_stat_id, current_real_balance, current_bonus_balance, current_bonus_win_locked_balance, current_loyalty_points, @bonusAdjustmentCounterID, NULL, pending_bets_real, pending_bets_bonus,withdrawal_pending_amount, 0, (gaming_client_stats.`total_loyalty_points_given_bonus` - gaming_client_stats.`total_loyalty_points_used_bonus`)
  FROM gaming_client_stats 
  JOIN gaming_bonus_adjustment_counter_clients AS bonus_adjustments ON 
    bonus_adjustments.bonus_adjustment_counter_id=@bonusAdjustmentCounterID AND 
    gaming_client_stats.client_stat_id=bonus_adjustments.client_stat_id
  JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id
  JOIN gaming_payment_transaction_type ON gaming_payment_transaction_type.name='BonusAdjustment';
  
  INSERT INTO gaming_game_plays 
  (amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, payment_transaction_type_id, balance_real_after, balance_bonus_after, currency_id, session_id, transaction_id, pending_bet_real, pending_bet_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus) 
  SELECT amount_total, amount_total_base, exchange_rate, amount_real, amount_bonus, amount_bonus_win_locked, timestamp, client_id, client_stat_id, gaming_transactions.payment_transaction_type_id, balance_real_after, balance_bonus_after+balance_bonus_win_locked_after, gaming_transactions.currency_id, gaming_transactions.session_id, gaming_transactions.transaction_id, pending_bet_real, pending_bet_bonus, gaming_transactions.loyalty_points, gaming_transactions.loyalty_points_after, gaming_transactions.loyalty_points_bonus, gaming_transactions.loyalty_points_after_bonus
  FROM gaming_transactions
  JOIN gaming_payment_transaction_type ON 
    gaming_transactions.extra_id=@bonusAdjustmentCounterID AND
    gaming_payment_transaction_type.name='BonusAdjustment' AND gaming_transactions.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id;
  
  CALL GameUpdateRingFencedBalances(@clientStatID,LAST_INSERT_ID());  
  
END$$

DELIMITER ;

