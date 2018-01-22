DROP procedure IF EXISTS `BonusGiveRuleActionFreeRoundBonuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGiveRuleActionFreeRoundBonuses`()
root: BEGIN
  DECLARE CWFreeRoundCounterID, bonusRuleAwardCounterID BIGINT DEFAULT -1;
  DECLARE bonusEnabledFlag TINYINT(1) DEFAULT 0;
  
  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  
  IF NOT (bonusEnabledFlag) THEN
    LEAVE root;

  END IF;
  
 --  insert into gaming_cw_free_rounds
	INSERT INTO gaming_cw_free_round_counter (timestamp) VALUES (NOW());	
	SET CWFreeRoundCounterID = LAST_INSERT_ID();

   INSERT INTO gaming_cw_free_rounds (client_stat_id, cw_free_round_status_id, date_created, cost_per_round, free_rounds_awarded, 
		free_rounds_remaining, win_total, game_manufacturer_id, bonus_rule_id, 
		expiry_date, wager_requirement_multiplier, cw_free_round_counter_id)
	SELECT gaming_client_stats.client_stat_id, cw_free_round_status_id, NOW(), cost_per_round, IFNULL(BonusesToAward.Price, gaming_bonus_free_round_profiles.num_rounds),
		IFNULL(BonusesToAward.Price, gaming_bonus_free_round_profiles.num_rounds),0,gaming_bonus_free_round_profiles.game_manufacturer_id,gaming_bonus_rules.bonus_rule_id,
		IFNULL(free_round_expiry_date,DATE_ADD(NOW(), INTERVAL free_round_expiry_days DAY)), gaming_bonus_rules.wager_requirement_multiplier, CWFreeRoundCounterID
   FROM gaming_bonus_rules 
   JOIN 
    (SELECT Price.value AS Price, BonusRuleID.value AS BonusRuleID, gaming_rules_instances.client_stat_id  
    FROM gaming_rules_instances
    JOIN gaming_rules_to_award ON gaming_rules_to_award.rule_instance_id = gaming_rules_instances.rule_instance_id AND awarded_state=2
    JOIN gaming_rule_actions ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id
    JOIN gaming_client_stats ON gaming_rules_instances.client_stat_id = gaming_client_stats.client_stat_id
    JOIN (
      SELECT gaming_rule_action_vars.value,gaming_rule_action_vars.rule_action_var_id,gaming_rule_action_vars.rule_action_id 
	  FROM gaming_rule_action_vars
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND gaming_rule_action_types_var_types.name='NumFreeRounds'
      )
      AS Price ON Price.rule_action_id = gaming_rule_actions.rule_action_id 
    JOIN ( 
      SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id 
	  FROM gaming_rule_action_vars
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND gaming_rule_action_types_var_types.name='BonusRuleID')
      AS BonusRuleID ON BonusRuleID.rule_action_id = gaming_rule_actions.rule_action_id
    JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = BonusRuleID.rule_action_type_id
    WHERE gaming_rule_action_types.name='FreeRound' 
    
    UNION ALL
    
    SELECT Price.value AS Price, BonusRuleID.value AS BonusRuleID, referral.client_stat_id 
    FROM gaming_rules_instances
    JOIN gaming_rules_to_award ON gaming_rules_to_award.rule_instance_id = gaming_rules_instances.rule_instance_id AND awarded_state=2
    JOIN gaming_rule_actions ON gaming_rules_instances.rule_id = gaming_rule_actions.rule_id AND gaming_rule_actions.award_referral=1
    JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = gaming_rules_instances.client_stat_id
    JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id
    JOIN gaming_client_stats AS referral ON referral.client_id = gaming_clients.referral_client_id
    JOIN (
      SELECT gaming_rule_action_vars.value,gaming_rule_action_vars.rule_action_var_id,gaming_rule_action_vars.rule_action_id 
	  FROM gaming_rule_action_vars
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND gaming_rule_action_types_var_types.name='NumFreeRounds'
      )
      AS Price ON Price.rule_action_id = gaming_rule_actions.rule_action_id 
    JOIN ( 
      SELECT value,rule_action_var_id,rule_action_id,rule_action_type_id 
	  FROM gaming_rule_action_vars
      JOIN gaming_rule_action_types_var_types ON gaming_rule_action_types_var_types.rule_action_type_var_id = gaming_rule_action_vars.rule_action_type_var_id AND gaming_rule_action_types_var_types.name='BonusRuleID')
      AS BonusRuleID ON BonusRuleID.rule_action_id = gaming_rule_actions.rule_action_id
    JOIN gaming_rule_action_types ON gaming_rule_action_types.rule_action_type_id = BonusRuleID.rule_action_type_id
    WHERE gaming_rule_action_types.name='FreeRound'
  ) AS BonusesToAward  ON BonusesToAward.BonusRuleID = gaming_bonus_rules.bonus_rule_id AND gaming_bonus_rules.is_free_rounds = 1
  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=BonusesToAward.client_stat_id
  JOIN gaming_bonus_rule_free_round_profiles AS gbrfrp ON gbrfrp.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
  JOIN gaming_bonus_free_round_profiles ON gaming_bonus_free_round_profiles.bonus_free_round_profile_id = gbrfrp.bonus_free_round_profile_id
  JOIN gaming_bonus_free_round_profiles_amounts ON gaming_bonus_free_round_profiles_amounts.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
		AND gaming_bonus_free_round_profiles_amounts.currency_id = gaming_client_stats.currency_id
  JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name ='OnAwarded';
  
  -- insert into gaming_bonus_instances
  IF (ROW_COUNT()>0) THEN
	
    INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
	SELECT -1, NOW();
  
	SET bonusRuleAwardCounterID=LAST_INSERT_ID();	

	INSERT INTO gaming_bonus_instances (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, bonus_rule_award_counter_id, transfer_every_x, transfer_every_amount,cw_free_round_id,is_free_rounds,is_free_rounds_mode) 
	SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, bonusRuleAwardCounterID, transfer_every_x, transfer_every_amount,cw_free_round_id,IF(cw_free_round_id IS NULL,0,1),IF(cw_free_round_id IS NULL,0,1)
	FROM
	(
		SELECT priority, bonus_amount, wager_requirement_multiplier, expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount ,cw_free_round_id
		FROM
		(
		  SELECT gaming_bonus_rules.priority, 0 AS bonus_amount, 
			IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
			gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_cw_free_rounds.client_stat_id,
			CASE gaming_bonus_types_release.name
			  WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
			  WHEN 'EveryReleaseAmount' THEN ROUND(gaming_bonus_rules.wager_requirement_multiplier/(0/wager_restrictions.release_every_amount),2)
			  ELSE NULL
			END AS transfer_every_x, 
			CASE gaming_bonus_types_release.name
			  WHEN 'EveryXWager' THEN ROUND(0/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
			  WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
			  ELSE NULL
			END AS transfer_every_amount,
			gaming_cw_free_rounds.cw_free_round_id
		  FROM gaming_cw_free_rounds  
		  STRAIGHT_JOIN gaming_bonus_rules ON gaming_cw_free_rounds.cw_free_round_counter_id=CWFreeRoundCounterID AND gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		  STRAIGHT_JOIN gaming_client_stats ON gaming_cw_free_rounds.client_stat_id = gaming_client_stats.client_stat_id  
		  LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
		  LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
		  LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
		) AS CB
	) AS XX;
   
	  SELECT COUNT(*) INTO @numPlayers
	  FROM gaming_bonus_instances FORCE INDEX (bonus_rule_award_counter_id)
	  JOIN gaming_client_stats ON gaming_bonus_instances.client_stat_id=gaming_client_stats.client_stat_id
	  WHERE gaming_bonus_instances.bonus_rule_award_counter_id=bonusRuleAwardCounterID 
	  FOR UPDATE; 

	  CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);
		  
  END IF;
END root$$

DELIMITER ;

