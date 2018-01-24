DROP procedure IF EXISTS `GameSessionGetPlayerActiveBonuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionGetPlayerActiveBonuses`(clientStatID BIGINT, operatorGameID BIGINT)
BEGIN
  SELECT gbi.bonus_instance_id, gbi.priority, gbi.bonus_amount_given, gbi.bonus_amount_remaining, gbi.total_amount_won, gbi.current_win_locked_amount, 
    gbi.bonus_wager_requirement, gbi.bonus_wager_requirement_remain, gbi.given_date, gbi.expiry_date, gbi.secured_date, gbi.lost_date, gbi.used_all_date, 
    gbi.is_secured, gbi.is_lost, gbi.is_used_all, gbi.is_active, 
	gbi.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, gbi.client_stat_id, gbi.extra_id, 
    gbi.bonus_transfered_total, gbi.transfer_every_x, gbi.transfer_every_amount, gbi.transfer_every_x_last, NULL AS reason , current_ring_fenced_amount, gaming_bonus_rules.is_generic,
    gbi.is_free_rounds,gbi.is_free_rounds_mode,gbi.cw_free_round_id
  FROM gaming_bonus_instances AS gbi 
  JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id=gaming_bonus_types.bonus_type_id
  JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.client_stat_id=clientStatID AND gbi.is_active) AND
  (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
  ORDER BY priority ASC, given_date DESC; 
END$$

DELIMITER ;

