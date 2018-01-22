DROP procedure IF EXISTS `BonusGetLostBonusesOnWithdrawal`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetLostBonusesOnWithdrawal`(clientStatID BIGINT, balanceHistoryID BIGINT)
BEGIN
	-- Added open_rounds
    -- Added TransactionWithdrawByUser
	
	DECLARE isActive,isLost TINYINT(1) DEFAULT 0;

	SET isActive = 1;

	SELECT gbi.bonus_instance_id, gbi.priority, bonus_amount_given, gaming_bonus_losts.bonus_amount AS bonus_amount_remaining ,
		total_amount_won,gaming_bonus_losts.bonus_win_locked_amount AS current_win_locked_amount, 
		bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date,NULL AS lost_date, used_all_date, 
		gbi.is_secured,isLost AS is_lost, gbi.is_used_all, isActive AS is_active, 
		gbi.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, gbi.client_stat_id, gbi.extra_id,
		bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last,gaming_bonus_rules.is_free_bonus,
		NULL AS reason,gaming_bonus_losts.ring_fenced_amount AS current_ring_fenced_amount, gaming_bonus_rules.is_generic,
		gbi.is_free_rounds,gbi.is_free_rounds_mode,gbi.cw_free_round_id, gaming_bonus_types_awarding.name as bonus_award_type, gbi.open_rounds
	FROM gaming_balance_history FORCE INDEX (PRIMARY)
	STRAIGHT_JOIN gaming_bonus_lost_types ON gaming_bonus_lost_types.name IN ('TransactionWithdraw', 'TransactionWithdrawByUser')
	STRAIGHT_JOIN gaming_bonus_losts ON gaming_balance_history.balance_history_id = gaming_bonus_losts.extra_id
		AND gaming_bonus_losts.bonus_lost_type_id = gaming_bonus_lost_types.bonus_lost_type_id
	STRAIGHT_JOIN gaming_bonus_instances AS gbi ON gbi.bonus_instance_id = gaming_bonus_losts.bonus_instance_id AND gbi.client_stat_id = clientStatID
	STRAIGHT_JOIN gaming_bonus_rules ON gbi.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	STRAIGHT_JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
    STRAIGHT_JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
	WHERE balance_history_id = balanceHistoryID;

END$$

DELIMITER ;

