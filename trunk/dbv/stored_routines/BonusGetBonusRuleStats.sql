DROP procedure IF EXISTS `BonusGetBonusRuleStats`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetBonusRuleStats`(bonusRuleID BIGINT)
root:BEGIN
  -- Optimized
  SET @bonusRuleID=bonusRuleID;
  SELECT given_date, gaming_clients.client_id AS player_id, CONCAT(gaming_clients.name,' ',surname) AS player_name,  
    IF (gaming_bonus_instances.is_active, 'Active', IF (is_secured, 'Requirement Met', IF(is_used_all, 'Used All', IF(is_lost, 'Lost', 'Unknown')))) AS status, gaming_currency.currency_code,
    bonus_amount_given AS bonus_amount_given, (bonus_amount_remaining+current_win_locked_amount) AS bonus_amount_remaining, total_amount_won/100 AS total_amount_won, 
    bonus_wager_requirement AS bonus_wager_requirement, bonus_wager_requirement_remain AS bonus_wager_requirement_remain,  expiry_date, 
    IFNULL(secured_date, IFNULL(lost_date, used_all_date)) AS status_date, gaming_bonus_instances.bonus_instance_id
  FROM gaming_bonus_instances
  JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id = gaming_client_stats.client_stat_id
  JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
  JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
  WHERE (@bonusRuleID=0 OR gaming_bonus_instances.bonus_rule_id=@bonusRuleID)
  ORDER BY gaming_bonus_instances.bonus_instance_id DESC;
END root$$

DELIMITER ;

