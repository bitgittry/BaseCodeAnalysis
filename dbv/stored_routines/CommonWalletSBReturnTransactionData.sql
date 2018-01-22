DROP procedure IF EXISTS `CommonWalletSBReturnTransactionData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSBReturnTransactionData`(gamePlayID BIGINT, sbBetID BIGINT, sbExtraID BIGINT, tranType VARCHAR(10), clientStatID BIGINT)
BEGIN
  -- Adding check on license_type
  -- Forcing Index
  
  SELECT game_play_id, game_round_id, gaming_payment_transaction_type.name AS transaction_type, amount_total, amount_total_base, amount_real, amount_ring_fenced, amount_bonus, amount_bonus_win_locked, amount_other, jackpot_contribution, bonus_lost, bonus_win_locked_lost, timestamp, exchange_rate, game_id, game_manufacturer_id, operator_game_id, client_stat_id, game_session_id, balance_real_after, balance_bonus_after, is_win_placed, is_processed, game_play_id_win, 
		amount_tax_operator, amount_tax_player, amount_tax_operator_bonus, amount_tax_player_bonus, loyalty_points, loyalty_points_after, loyalty_points_bonus,loyalty_points_after_bonus, amount_cash  
  FROM gaming_game_plays 
  STRAIGHT_JOIN gaming_payment_transaction_type ON gaming_game_plays.payment_transaction_type_id=gaming_payment_transaction_type.payment_transaction_type_id
  WHERE gaming_game_plays.game_play_id=gamePlayID AND gaming_game_plays.license_type_id=3;
   
  SELECT SUM(amount_total*sign_mult*IF(tranType='Bet',-1,1)) AS amount_total, SUM(amount_real*sign_mult*IF(tranType='Bet',-1,1)) AS amount_real, SUM((amount_bonus+amount_bonus_win_locked+bonus_lost+bonus_win_locked_lost)*sign_mult*IF(tranType='Bet',-1,1)) AS amount_bonus, sb_bet_id, sb_extra_id 
  FROM gaming_game_plays FORCE INDEX (sb_bet_single_id)
  WHERE sb_bet_id=sbBetID AND sb_extra_id=sbExtraID AND 
	((tranType='Bet' AND payment_transaction_type_id IN (12,20,45,47)) 
		OR (tranType='Win' AND payment_transaction_type_id IN (13,30,46)))
    AND gaming_game_plays.license_type_id=3;
  
  SELECT current_real_balance+current_bonus_balance+current_bonus_win_locked_balance AS current_balance, current_real_balance, 
    current_bonus_balance+current_bonus_win_locked_balance AS current_bonus_balance, pl_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate,5) AS exchange_rate ,
	current_ring_fenced_amount,current_ring_fenced_sb,current_ring_fenced_casino,current_ring_fenced_poker
  FROM gaming_client_stats  
  STRAIGHT_JOIN gaming_currency AS pl_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=pl_currency.currency_id
  STRAIGHT_JOIN gaming_operators ON gaming_operators.is_main_operator=1
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=pl_currency.currency_id; 
    
END$$

DELIMITER ;

