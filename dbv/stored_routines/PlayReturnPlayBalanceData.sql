DROP procedure IF EXISTS `PlayReturnPlayBalanceData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayReturnPlayBalanceData`(clientStatID BIGINT, operatorGameID BIGINT)
BEGIN
  
  SELECT 
	  IF (gaming_operator_games.disable_bonus_money=1, current_real_balance, 
		ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0), 0)) AS current_balance, 
	  current_real_balance, 
      IF (gaming_operator_games.disable_bonus_money=1, 0, ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0), 0)) AS current_bonus_balance, 
      gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
	  current_ring_fenced_amount, current_ring_fenced_sb, current_ring_fenced_casino, current_ring_fenced_poker,
	  gaming_client_stats.current_free_rounds_amount, gaming_client_stats.current_free_rounds_num, gaming_client_stats.current_free_rounds_win_locked, gaming_client_stats.deferred_tax
  FROM gaming_client_stats  
  JOIN gaming_currency ON gaming_client_stats.client_stat_id=clientStatID AND gaming_client_stats.currency_id=gaming_currency.currency_id 
  LEFT JOIN gaming_operator_games ON gaming_operator_games.operator_game_id=operatorGameID
  LEFT JOIN gaming_operators ON gaming_operator_games.operator_id = gaming_operators.operator_id
  LEFT JOIN
  (
    SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
    FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
    STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON 
	  (gbi.client_stat_id=clientStatID AND gbi.is_active) AND
      (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
  ) AS Bonuses ON 1=1
  LEFT JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id 
  LEFT JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
  LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_game_manufacturers.cw_exchange_currency
  LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id 
  LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id 
  LIMIT 1; 
  
  SELECT NULL;
 
END$$

DELIMITER ;

