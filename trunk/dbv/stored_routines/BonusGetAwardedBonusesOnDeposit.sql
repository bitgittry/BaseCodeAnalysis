DROP procedure IF EXISTS `BonusGetAwardedBonusesOnDeposit`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetAwardedBonusesOnDeposit`(clientStatID BIGINT, balanceHistoryID BIGINT)
BEGIN
  -- Added open_rounds
  
  SELECT bonus.bonus_instance_id, bonus.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
    bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
    bonus.is_secured, bonus.is_lost, bonus.is_used_all, bonus.is_active, 
    bonus.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, bonus.client_stat_id, bonus.extra_id,
    bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last,gaming_bonus_rules.is_free_bonus,
    CONCAT('Deposited On: ', deposit_transaction.timestamp, ' , Amount: ', deposit_transaction.amount/100) AS reason,current_ring_fenced_amount, gaming_bonus_rules.is_generic,
	bonus.is_free_rounds,bonus.is_free_rounds_mode,bonus.cw_free_round_id, gaming_bonus_types_awarding.name as bonus_award_type, bonus.open_rounds
  FROM gaming_balance_history AS deposit_transaction
  JOIN gaming_bonus_instances AS bonus ON bonus.client_stat_id=clientStatID AND bonus.extra_id=deposit_transaction.balance_history_id
  JOIN gaming_bonus_rules ON bonus.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_types ON gaming_bonus_types.name='Deposit' AND gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
  JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
  WHERE deposit_transaction.balance_history_id=balanceHistoryID;
END$$

DELIMITER ;

