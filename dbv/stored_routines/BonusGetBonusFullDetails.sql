DROP procedure IF EXISTS `BonusGetBonusFullDetails`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusFullDetails`(bonusInstanceID BIGINT, returnPlayRows TINYINT(1))
BEGIN

  -- Optimized	 

  SELECT bonus.bonus_instance_id, bonus.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
    bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
    bonus.is_secured, bonus.is_lost, bonus.is_used_all, bonus.is_active, 
    bonus.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, bonus.client_stat_id, bonus.extra_id,
    bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last,gaming_bonus_rules.is_free_bonus,current_ring_fenced_amount,max_count_per_interval, is_generic,
    CASE gaming_bonus_types.name 
      WHEN 'Manual' THEN CONCAT('User: ', manual_user.username, ', Reason: ', bonus.reason)
      WHEN 'Login' THEN CONCAT('Logged In On: ', login_session.date_open)
      WHEN 'Deposit' THEN CONCAT('Deposited On: ', deposit_transaction.timestamp, ' , Amount: ', deposit_transaction.amount/100)
      WHEN 'DirectGive' THEN CONCAT('')
      WHEN 'FreeRound' THEN CONCAT('')
      WHEN 'Reward' THEN CONCAT('')
      WHEN 'BonusForPromotion' THEN CONCAT('Promotion Prize: ',gaming_promotions.description)
    END AS reason,bonus.is_free_rounds,bonus.is_free_rounds_mode,bonus.cw_free_round_id
  FROM gaming_bonus_instances AS bonus FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_bonus_rules ON bonus.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
  STRAIGHT_JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
  LEFT JOIN sessions_main AS manual_session ON gaming_bonus_types.name='Manual' AND bonus.extra_id=manual_session.session_id
  LEFT JOIN users_main AS manual_user ON manual_session.user_id=manual_user.user_id
  LEFT JOIN sessions_main AS login_session ON gaming_bonus_types.name='Login' AND bonus.extra_id=login_session.session_id   
  LEFT JOIN gaming_balance_history AS deposit_transaction ON gaming_bonus_types.name='Deposit' AND bonus.extra_id=deposit_transaction.balance_history_id
  LEFT JOIN gaming_promotions ON gaming_bonus_types.name='BonusForPromotion' AND bonus.extra_id=gaming_promotions.promotion_id  
  WHERE bonus.bonus_instance_id=bonusInstanceID;
  
  IF (returnPlayRows) THEN
    SELECT game_play_bonus_instance_id, gaming_game_plays_bonus_instances.game_play_id, bonus_instance_id, wager_requirement_non_weighted, wager_requirement_contribution, bet_bonus, bet_bonus_win_locked, 
      win_bonus, win_bonus_win_locked, lost_win_bonus, lost_win_bonus_win_locked, now_used_all, now_wager_requirement_met, bonus_transfered, bonus_win_locked_transfered, bet_ring_fenced, win_ring_fenced
    FROM gaming_game_plays_bonus_instances FORCE INDEX (bonus_instance_id)
    WHERE gaming_game_plays_bonus_instances.bonus_instance_id=bonusInstanceID; 
  ELSE
    SELECT NULL;
  END IF;
  
  SELECT gaming_bonus_losts.bonus_lost_id, gaming_bonus_losts.bonus_instance_id, gaming_bonus_losts.client_stat_id, gaming_bonus_lost_types.name AS 'bonus_lost_type', bonus_amount, bonus_win_locked_amount, gaming_bonus_losts.extra_id, date_time_lost
  FROM gaming_bonus_losts FORCE INDEX (bonus_instance_id)
  STRAIGHT_JOIN gaming_bonus_lost_types ON gaming_bonus_losts.bonus_lost_type_id=gaming_bonus_lost_types.bonus_lost_type_id 
  WHERE gaming_bonus_losts.bonus_instance_id=bonusInstanceID; 
  
SELECT * FROM
(
  SELECT transaction_id, bonus_awarded.payment_transaction_type_id AS transaction_type_id, bonus_awarded.name AS transaction_type_name, 
    amount_total, amount_total_base, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, 
    gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
    loyalty_points_after, gaming_transactions.reason, currency_code, gaming_transactions.balance_history_id 
  FROM gaming_payment_transaction_type AS bonus_awarded 
  STRAIGHT_JOIN gaming_bonus_instances ON 
	bonus_awarded.name='BonusAwarded' AND
	gaming_bonus_instances.bonus_instance_id=bonusInstanceID
  STRAIGHT_JOIN gaming_transactions FORCE INDEX (extra_id) ON
	gaming_transactions.extra_id=gaming_bonus_instances.bonus_instance_id AND gaming_transactions.payment_transaction_type_id = bonus_awarded.payment_transaction_type_id  
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_bonus_instances.client_stat_id
  STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id
  LIMIT 1
) AS X1
UNION ALL
(
  SELECT transaction_id, bonus_lost.payment_transaction_type_id AS transaction_type_id, bonus_lost.name AS transaction_type_name, 
    amount_total, amount_total_base, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, 
    gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
    loyalty_points_after, gaming_transactions.reason, currency_code, gaming_transactions.balance_history_id 
  FROM gaming_payment_transaction_type AS bonus_lost 
  JOIN gaming_bonus_instances ON 
	bonus_lost.name='BonusLost' AND
	gaming_bonus_instances.bonus_instance_id=bonusInstanceID
  STRAIGHT_JOIN gaming_bonus_lost_counter_bonus_instances AS counter_bonus_lost ON counter_bonus_lost.bonus_instance_id=gaming_bonus_instances.bonus_instance_id
  STRAIGHT_JOIN gaming_transactions FORCE INDEX (extra_id) ON
	gaming_transactions.extra_id=counter_bonus_lost.bonus_lost_counter_id AND gaming_transactions.payment_transaction_type_id=bonus_lost.payment_transaction_type_id
  STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_bonus_instances.client_stat_id
  STRAIGHT_JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id
  LIMIT 1
) 
UNION ALL
(
  SELECT transaction_id, bonus_req_met.payment_transaction_type_id AS transaction_type_id, bonus_req_met.name AS transaction_type_name, 
    amount_total, amount_total_base, amount_real, amount_bonus, amount_bonus_win_locked, amount_cashback, loyalty_points, 
    gaming_transactions.timestamp, gaming_transactions.exchange_rate, gaming_transactions.client_stat_id, balance_real_after, balance_bonus_after, balance_bonus_win_locked_after, 
    loyalty_points_after, gaming_transactions.reason,currency_code,gaming_transactions.balance_history_id 
  FROM gaming_payment_transaction_type AS bonus_req_met 
  STRAIGHT_JOIN gaming_bonus_instances ON 
	bonus_req_met.name='BonusRequirementMet' AND
	gaming_bonus_instances.bonus_instance_id=bonusInstanceID
  STRAIGHT_JOIN gaming_game_plays_bonus_instances AS play_bonus_instances ON 
	play_bonus_instances.bonus_instance_id=gaming_bonus_instances.bonus_instance_id AND play_bonus_instances.now_wager_requirement_met=1 
  JOIN gaming_transactions FORCE INDEX (extra_id) ON 
	gaming_transactions.extra_id=play_bonus_instances.game_play_id AND gaming_transactions.payment_transaction_type_id=bonus_req_met.payment_transaction_type_id
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_bonus_instances.client_stat_id
  JOIN gaming_currency ON gaming_currency.currency_id = gaming_client_stats.currency_id
  LIMIT 1
);
  
END$$

DELIMITER ;

