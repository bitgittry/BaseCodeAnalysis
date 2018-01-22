DROP procedure IF EXISTS `PlayReturnDataWithoutGame`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayReturnDataWithoutGame`(
  gamePlayID BIGINT, gameRoundID BIGINT, clientStatID BIGINT, gameManufacturerID BIGINT, minimalData TINYINT(1))
BEGIN
  
  -- Optimized
  -- Remove reference to gaming_bonus_free_rounds 
  
  IF (minimalData) THEN
  
	SELECT game_play_id, amount_total, amount_total_base, amount_real, amount_cash,
		amount_ring_fenced, amount_bonus, amount_bonus_win_locked, timestamp, exchange_rate
	FROM gaming_game_plays 
    WHERE gaming_game_plays.game_play_id=gamePlayID;
    
    SELECT gameRoundID AS game_round_id;
  
  ELSE 
  
	  SELECT game_play_id, game_round_id, gaming_payment_transaction_type.name AS transaction_type, 
		amount_total, amount_total_base, amount_real, amount_cash, amount_ring_fenced, 
		amount_bonus, amount_bonus_win_locked, amount_other, jackpot_contribution, bonus_lost, bonus_win_locked_lost, 
		timestamp, exchange_rate, game_id, game_manufacturer_id, operator_game_id, client_stat_id, game_session_id, 
		balance_real_after, balance_bonus_after, is_win_placed, is_processed, game_play_id_win, amount_tax_operator, amount_tax_player, 
		loyalty_points, loyalty_points_after, loyalty_points_bonus, loyalty_points_after_bonus, pending_winning_real,
		sb_bet_id, sb_extra_id, is_confirmed, confirmed_amount
	  FROM gaming_game_plays FORCE INDEX (PRIMARY)
	  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
	  WHERE game_play_id=gamePlayID;
	  
	  SELECT game_round_id, bet_total, bet_total_base, bet_real,bet_cash, bet_bonus, bet_bonus_win_locked, jackpot_contribution, win_total, win_total_base, 
		win_real, win_cash, win_bonus, win_bonus_win_locked, bonus_lost, bonus_win_locked_lost, date_time_start, date_time_end, 
		is_round_finished, game_id, game_manufacturer_id, operator_game_id, client_stat_id, balance_real_after, balance_bonus_after, num_bets, 
		gaming_game_round_types.name AS round_type, round_ref, amount_tax_operator, amount_tax_player , balance_real_before, balance_bonus_before, 
		loyalty_points, loyalty_points_bonus, round_ref, amount_tax_operator, amount_tax_player, loyalty_points, loyalty_points_bonus
	  FROM gaming_game_rounds FORCE INDEX (PRIMARY)
	  STRAIGHT_JOIN gaming_game_round_types ON gaming_game_rounds.game_round_type_id=gaming_game_round_types.game_round_type_id
	  WHERE gaming_game_rounds.game_round_id=gameRoundID;
  
  END IF;
  
  SELECT current_real_balance+current_bonus_balance+current_bonus_win_locked_balance AS current_balance, 
	current_real_balance, current_bonus_balance+current_bonus_win_locked_balance AS current_bonus_balance, 
    gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/IFNULL(gm_exchange_rate.exchange_rate,1),5) AS exchange_rate   
  FROM gaming_client_stats FORCE INDEX (PRIMARY)
  STRAIGHT_JOIN gaming_currency ON 
    gaming_client_stats.currency_id=gaming_currency.currency_id 
  STRAIGHT_JOIN gaming_operators ON 
	gaming_operators.is_main_operator=1
  STRAIGHT_JOIN gaming_game_manufacturers ON 
	gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID
  LEFT JOIN gaming_currency AS gm_currency ON 
	gm_currency.currency_code=gaming_game_manufacturers.cw_exchange_currency
  LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON 
	gaming_operators.operator_id=gm_exchange_rate.operator_id AND
    gm_currency.currency_id=gm_exchange_rate.currency_id 
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON 
	gaming_operators.operator_id=pl_exchange_rate.operator_id AND 
    pl_exchange_rate.currency_id=gaming_currency.currency_id
  WHERE gaming_client_stats.client_stat_id=clientStatID;
  
  SELECT NULL;
  
END$$

DELIMITER ;

