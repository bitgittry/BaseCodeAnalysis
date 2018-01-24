DROP procedure IF EXISTS `BonusGetBonusKPI`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusKPI`(pBonusRuleID BIGINT, testPlayers TINYINT(1))
BEGIN
    -- Optimized
	DECLARE isTypeTwo TINYINT(1) DEFAULT 0;

	SELECT operator_id INTO @operatorID FROM gaming_operators WHERE is_main_operator=1 LIMIT 1; 
	SELECT value_string='Type2' INTO isTypeTwo FROM gaming_settings where name = 'PLAY_WAGER_TYPE';

	SELECT 
	  COUNT(gaming_bonus_instances.bonus_instance_id) `BonusAwarded_PlayerCount`,	ROUND(SUM(bonus_amount_given)/100,2) `BonusAwarded`, ROUND(SUM(bonus_amount_given / gaming_operator_currency.exchange_rate)/100,2) `BonusAwarded_BaseCurrency`,
	  SUM(is_secured) `BonusTurnedReal_PlayerCount`, ROUND(SUM(bonus_transfered_total / gaming_operator_currency.exchange_rate)/ 100,2) AS `BonusTurnedReal_BaseCurrency`
	FROM gaming_bonus_instances FORCE INDEX(bonus_rule_id)
	JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id				
	JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND (gaming_clients.is_test_player = 0 OR testPlayers=1)
	JOIN gaming_operator_currency ON gaming_operator_currency.operator_id=@operatorID AND gaming_operator_currency.currency_id=gaming_client_stats.currency_id
	WHERE  gaming_bonus_instances.bonus_rule_id=pBonusRuleID;
	
	SELECT ROUND(SUM(bet_real)/100,2)  `RealMoneyBets_BaseCurrency`, SUM(bet_bonus)/100 `BonusBets_BaseCurrency`,
		CASE isTypeTwo
			WHEN 1 THEN SUM(win_real)/100 
			ELSE -1
		END `RealMoneyWins_BaseCurrency`,
		ROUND(SUM(win_bonus)/100,2) `BonusMoneyWins_BaseCurrency`
	FROM gaming_game_transactions_aggregation_bonus  				
	WHERE bonus_rule_id=pBonusRuleID  AND (gaming_game_transactions_aggregation_bonus.test_players = 0 OR testPlayers=1);

	SELECT 		
      ROUND(SUM(IF(gaming_bonus_lost_types.`Name` != 'Expired', gaming_bonus_losts.bonus_amount+gaming_bonus_losts.bonus_win_locked_amount, 0)/gaming_operator_currency.exchange_rate)/100,2)  `BonusForfeited_BaseCurrency`,
	  ROUND(SUM(IF(gaming_bonus_lost_types.`Name` = 'Expired', gaming_bonus_losts.bonus_amount+gaming_bonus_losts.bonus_win_locked_amount, 0)/gaming_operator_currency.exchange_rate)/100,2) `BonusExpired_BaseCurrency`
	FROM gaming_bonus_instances FORCE INDEX (bonus_rule_id)
	JOIN gaming_bonus_losts ON gaming_bonus_instances.bonus_instance_id = gaming_bonus_losts.bonus_instance_id
	JOIN gaming_bonus_lost_types FORCE INDEX (PRIMARY) ON gaming_bonus_losts.bonus_lost_type_id = gaming_bonus_lost_types.bonus_lost_type_id
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_bonus_losts.client_stat_id
	JOIN gaming_clients ON gaming_clients.client_id = gaming_client_stats.client_id AND (gaming_clients.is_test_player = 0 OR testPlayers=1)
	JOIN gaming_operator_currency ON gaming_operator_currency.operator_id=@operatorID AND gaming_operator_currency.currency_id=gaming_client_stats.currency_id
	WHERE gaming_bonus_instances.bonus_rule_id=pBonusRuleID AND gaming_bonus_instances.is_lost=1;  
	
END$$

DELIMITER ;

