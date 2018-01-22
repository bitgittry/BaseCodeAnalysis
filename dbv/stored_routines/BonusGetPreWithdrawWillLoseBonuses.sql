DROP procedure IF EXISTS `BonusGetPreWithdrawWillLoseBonuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetPreWithdrawWillLoseBonuses`(clientStatID BIGINT)
BEGIN
  -- Added open_rounds
  
  SELECT bonus.bonus_instance_id, bonus.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
    bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
    bonus.is_secured, bonus.is_lost, bonus.is_used_all, bonus.is_active, 
    bonus.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, bonus.client_stat_id, bonus.extra_id,
    bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last, NULL as reason,  current_ring_fenced_amount, gaming_bonus_rules.is_generic,
	bonus.is_free_rounds,bonus.is_free_rounds_mode,bonus.cw_free_round_id, gaming_bonus_types_awarding.name as bonus_award_type, bonus.open_rounds
  FROM gaming_bonus_instances AS bonus 
  JOIN gaming_bonus_rules ON bonus.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
  JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
  
  WHERE bonus.client_stat_id=clientStatID AND bonus.is_active=1 AND gaming_bonus_rules.forfeit_on_withdraw=1; 
END$$

DELIMITER ;

