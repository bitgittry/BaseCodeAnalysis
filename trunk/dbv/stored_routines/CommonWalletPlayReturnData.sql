DROP procedure IF EXISTS `CommonWalletPlayReturnData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletPlayReturnData`(cwTransactionID BIGINT)
BEGIN
  
  -- Addded Sb fields
  
  DECLARE clientStatID, gamePlayID, gameRoundID, operatorGameID, gameManufacturerID BIGINT DEFAULT -1;
  
  SELECT gaming_game_plays.client_stat_id, gaming_game_plays.game_play_id, gaming_game_plays.game_round_id, 
	gaming_operator_games.operator_game_id, IFNULL(gaming_game_plays.game_manufacturer_id, gaming_cw_transactions.game_manufacturer_id)
  INTO clientStatID, gamePlayID, gameRoundID, operatorGameID, gameManufacturerID
  FROM gaming_cw_transactions
  JOIN gaming_game_plays ON gaming_cw_transactions.cw_transaction_id=cwTransactionID AND gaming_cw_transactions.game_play_id=gaming_game_plays.game_play_id
  LEFT JOIN gaming_games ON 
	(gaming_game_plays.game_id IS NOT NULL AND gaming_games.game_id=gaming_game_plays.game_id) OR 
    (gaming_game_plays.game_id IS NULL AND gaming_games.game_manufacturer_id=gaming_cw_transactions.game_manufacturer_id AND gaming_games.manufacturer_game_idf=gaming_cw_transactions.game_ref)
  LEFT JOIN gaming_operator_games ON gaming_operator_games.game_id=gaming_games.game_id
  LIMIT 1;
  
  SELECT game_play_id, game_round_id, gaming_payment_transaction_type.name AS transaction_type, amount_total, amount_total_base, 
    amount_real, amount_cash,amount_ring_fenced, amount_bonus, amount_bonus_win_locked, amount_other, jackpot_contribution, 
    bonus_lost, bonus_win_locked_lost, timestamp, exchange_rate, game_id, game_manufacturer_id, operator_game_id, client_stat_id, game_session_id, 
    balance_real_after, balance_bonus_after, is_win_placed, is_processed, game_play_id_win, amount_tax_operator, amount_tax_player, loyalty_points, 
    loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, pending_winning_real,
	sb_bet_id, sb_extra_id, is_confirmed, confirmed_amount
  FROM gaming_game_plays 
  JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  WHERE game_play_id=gamePlayID;
  
  SELECT game_round_id, bet_total, bet_total_base, bet_real,bet_cash, bet_bonus, bet_bonus_win_locked, jackpot_contribution, win_total, win_total_base, win_real,win_cash, win_bonus, win_bonus_win_locked, bonus_lost, bonus_win_locked_lost, date_time_start, date_time_end, is_round_finished, game_id, game_manufacturer_id, operator_game_id, client_stat_id, balance_real_after, balance_bonus_after, num_bets, gaming_game_round_types.name AS round_type, round_ref, amount_tax_operator, amount_tax_player, balance_real_before, balance_bonus_before, loyalty_points, loyalty_points_bonus
  FROM gaming_game_rounds 
  JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
  WHERE game_round_id=gameRoundID;
  
  
  SELECT IF (gaming_operator_games.disable_bonus_money=1, current_real_balance, ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance+IF(cw_freerounds_addtobonus, IFNULL(FreeRounds.free_rounds_balance, 0), 0),0),0)) AS current_balance, current_real_balance, 
    IF(gaming_operator_games.disable_bonus_money=1, 0, ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance+IF(cw_freerounds_addtobonus, IFNULL(FreeRounds.free_rounds_balance, 0), 0),0),0)) AS current_bonus_balance, gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate  ,
    gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker,
    gaming_client_stats.current_free_rounds_amount, gaming_client_stats.current_free_rounds_num, gaming_client_stats.current_free_rounds_win_locked
  FROM gaming_client_stats  
  JOIN gaming_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id
  LEFT JOIN gaming_operator_games ON gaming_operator_games.operator_game_id=operatorGameID
  LEFT JOIN
  (
    SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
    FROM gaming_bonus_instances AS gbi
    JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.client_stat_id=clientStatID AND gbi.is_active) AND
      (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
  ) AS Bonuses ON 1=1
  LEFT JOIN
  (
    SELECT SUM(num_rounds_remaining * gbrfra.max_bet) AS free_rounds_balance 
    FROM gaming_bonus_free_rounds AS gbfr
    JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gbfr.client_stat_id=gaming_client_stats.client_stat_id AND gbfr.is_active
    JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_client_stats.currency_id
    JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbfr.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
  ) AS FreeRounds ON 1=1
  LEFT JOIN gaming_operators ON gaming_operators.is_main_operator=1
  LEFT JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID
  LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_game_manufacturers.cw_exchange_currency
  LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; 
  
  
  SELECT bonus_free_round_id, priority, num_rounds_given, num_rounds_remaining, total_amount_won, bonus_transfered_total, given_date, expiry_date, lost_date, used_all_date, 
    is_lost, is_used_all, gbfr.is_active, gbfr.bonus_rule_id, gbfr.client_stat_id, gbrfra.min_bet, gbrfra.max_bet  
  FROM gaming_bonus_free_rounds AS gbfr
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gbfr.client_stat_id=gaming_client_stats.client_stat_id AND gbfr.is_active
  JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_client_stats.currency_id
  JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbfr.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
  ORDER BY given_date DESC;
	
END$$

DELIMITER ;

