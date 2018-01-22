DROP procedure IF EXISTS `CommonWalletSBReturnDataOnCancelBet`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletSBReturnDataOnCancelBet`(clientStatID BIGINT, sbBetID BIGINT)
BEGIN
  -- Adding check on license_type
  -- Forcing Index
  SELECT IFNULL(SUM(amount_total),0) AS amount_total, IFNULL(SUM(amount_real),0) AS amount_real, IFNULL(SUM(amount_bonus),0) AS amount_bonus, IFNULL(SUM(amount_bonus_win_locked),0) AS amount_bonus_win_locked
  FROM gaming_game_plays FORCE INDEX (sb_bet_single_id)
  WHERE gaming_game_plays.sb_bet_id=sbBetID AND gaming_game_plays.payment_transaction_type_id=12 AND gaming_game_plays.is_win_placed=0 AND gaming_game_plays.license_type_id=3;
    
  SELECT current_real_balance+current_bonus_balance+current_bonus_win_locked_balance AS current_balance, current_real_balance, 
    current_bonus_balance+current_bonus_win_locked_balance AS current_bonus_balance, pl_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate,5) AS exchange_rate, 
	current_ring_fenced_amount,current_ring_fenced_sb,current_ring_fenced_casino,current_ring_fenced_poker
  FROM gaming_client_stats  
  STRAIGHT_JOIN gaming_currency AS pl_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=pl_currency.currency_id
  STRAIGHT_JOIN gaming_operators ON gaming_operators.is_main_operator=1
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=pl_currency.currency_id;   
    
END$$

DELIMITER ;

