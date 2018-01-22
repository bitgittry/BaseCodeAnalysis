
DROP procedure IF EXISTS `BonusGetBonusRuleFreeRoundStats`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusRuleFreeRoundStats`(bonusRuleID BIGINT)
root:BEGIN
  -- Optimized
  SET @bonusRuleID=bonusRuleID;
  SELECT given_date, gaming_clients.client_id AS player_id, CONCAT(gaming_clients.name,' ',surname) AS player_name,  
    IF (gbfr.is_active, 'Active', IF (num_rounds_remaining=0, 'Used All', IF(is_lost, 'Lost', 'Unknown'))) AS status, gaming_currency.currency_code,
    num_rounds_given, num_rounds_remaining, total_amount_won, 
    IFNULL(lost_date, used_all_date) AS status_date, gbrfra.min_bet, gbrfra.max_bet, bonus_free_round_id
  FROM gaming_bonus_free_rounds AS gbfr
  JOIN gaming_client_stats ON gbfr.client_stat_id = gaming_client_stats.client_stat_id
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
  JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_currency.currency_id
  WHERE (@bonusRuleID=0 OR gbfr.bonus_rule_id=@bonusRuleID) 
  ORDER BY gbfr.bonus_free_round_id DESC; 
END root$$

DELIMITER ;

