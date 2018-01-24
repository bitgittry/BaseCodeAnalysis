DROP procedure IF EXISTS `BonusGetPlayerBonuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGetPlayerBonuses`(bonusInstanceID BIGINT, clientStatID BIGINT, activeOnly TINYINT(1))
BEGIN
  -- Added open_rounds

  IF (clientStatID=0 AND bonusInstanceID!=0) THEN
	SELECT client_stat_id INTO clientStatID FROM gaming_bonus_instances WHERE bonus_instance_id=bonusInstanceID;
  END IF;

  SELECT bonus.bonus_instance_id, bonus.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
    bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
    bonus.is_secured, bonus.is_lost, bonus.is_used_all, bonus.is_active, 
    bonus.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, bonus.client_stat_id, bonus.extra_id,
    bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last,current_ring_fenced_amount,
    CASE gaming_bonus_types.name 
      WHEN 'Manual' THEN CONCAT('User: ', manual_user.username, ', Reason: ', bonus.reason)
      WHEN 'Login' THEN CONCAT('Logged In On: ', login_session.date_open)
      WHEN 'Deposit' THEN CONCAT('Deposited On: ', deposit_transaction.timestamp, ' , Amount: ', deposit_transaction.amount/100)
      WHEN 'DirectGive' THEN CONCAT('')
      WHEN 'FreeRound' THEN CONCAT('')
      WHEN 'Reward' THEN CONCAT('')
      WHEN 'BonusForPromotion' THEN CONCAT('Promotion Prize: ',gaming_promotions.description)
    END AS reason, gaming_bonus_rules.is_generic,bonus.is_free_rounds,bonus.is_free_rounds_mode,bonus.cw_free_round_id,  gaming_bonus_types_awarding.name as bonus_award_type,
    bonus.open_rounds
  FROM gaming_bonus_instances AS bonus
  JOIN gaming_bonus_rules ON bonus.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
  JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
  LEFT JOIN sessions_main AS manual_session ON gaming_bonus_types.name='Manual' AND bonus.extra_id=manual_session.session_id
  LEFT JOIN users_main AS manual_user ON manual_session.user_id=manual_user.user_id
  LEFT JOIN sessions_main AS login_session ON gaming_bonus_types.name='Login' AND bonus.extra_id=login_session.session_id   
  LEFT JOIN gaming_balance_history AS deposit_transaction ON gaming_bonus_types.name='Deposit' AND bonus.extra_id=deposit_transaction.balance_history_id
  LEFT JOIN gaming_promotions ON gaming_bonus_types.name='BonusForPromotion' AND bonus.extra_id=gaming_promotions.promotion_id  
  WHERE (bonusInstanceID=0 OR bonus.bonus_instance_id=bonusInstanceID) AND bonus.client_stat_id=clientStatID AND (activeOnly=0 OR bonus.is_active=1) 
  ORDER BY given_date DESC;


END$$

DELIMITER ;

