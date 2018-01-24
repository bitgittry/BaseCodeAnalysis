DROP procedure IF EXISTS `BonusGiveDirectGiveBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusGiveDirectGiveBonus`(bonusRuleID BIGINT, clientStatID BIGINT,balanceHistoryID BIGINT, OUT bonusInstanceGenID BIGINT)
BEGIN

	DECLARE bonusPreAuth,isFreeRounds TINYINT(1);
	DECLARE awardingType VARCHAR(80);
	DECLARE freeRoundExpiryDate,expiryDateFixed DATETIME;
	DECLARE freeRoundExpiryDays,expiryDaysFromAwarding,wagerRequirementMultiplier,numFreeRounds INT;

	SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';

	SELECT is_free_rounds,free_round_expiry_date,free_round_expiry_days, expiry_date_fixed, expiry_days_from_awarding,wager_requirement_multiplier,IFNULL(gaming_bonus_rules.num_free_rounds,num_rounds)
	INTO isFreeRounds,freeRoundExpiryDate,freeRoundExpiryDays,expiryDateFixed,expiryDaysFromAwarding,wagerRequirementMultiplier,numFreeRounds
	FROM gaming_bonus_rules 
    LEFT JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
	LEFT JOIN gaming_bonus_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
	WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID
	LIMIT 1; #if multiple profiles are linked to that bonus rule, only one will be selected(they have same cost per spin and number of rounds)

	IF (isFreeRounds = 0) THEN 
		IF (bonusPreAuth=0) THEN
			INSERT INTO gaming_bonus_instances (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount,extra_id) 
			SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount,balanceHistoryID
			FROM
			(
			  SELECT priority, bonus_amount, wager_requirement_multiplier, expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount 
			  FROM
			  (
				SELECT priority, bonus_amount, wager_requirement_multiplier, expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount 
				FROM
				(
				  SELECT gaming_bonus_rules.priority, gaming_bonus_rules_direct_gvs_amounts.amount AS bonus_amount, 
					IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
					gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id,
					CASE gaming_bonus_types_release.name
					  WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
					  WHEN 'EveryReleaseAmount' THEN ROUND(gaming_bonus_rules.wager_requirement_multiplier/(gaming_bonus_rules_direct_gvs_amounts.amount/wager_restrictions.release_every_amount),2)
					  ELSE NULL
					END AS transfer_every_x, 
					CASE gaming_bonus_types_release.name
					  WHEN 'EveryXWager' THEN ROUND(gaming_bonus_rules_direct_gvs_amounts.amount/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0)
					  WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
					  ELSE NULL
					END AS transfer_every_amount
				  FROM gaming_bonus_rules 
				  JOIN gaming_bonus_rules_direct_gvs ON 
					gaming_bonus_rules.bonus_rule_id=bonusRuleID AND 
					gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
				  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
				  JOIN gaming_bonus_rules_direct_gvs_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_client_stats.currency_id 
				  LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
				  LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
				  LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
				) AS CB
				WHERE CB.client_stat_id NOT IN (SELECT client_stat_id FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=bonusRuleID)
				ORDER BY RAND()
			  ) AS XX
			) AS XX
			LIMIT 1;
		   
			SET @rowCount=ROW_COUNT();

			IF (@rowCount > 0) THEN

				SET @bonusInstanceID=LAST_INSERT_ID();

				
				IF (@rowCount>0) THEN
					CALL BonusOnAwardedUpdateStats(@bonusInstanceID);

					SELECT gaming_bonus_types_awarding.name INTO awardingType
					FROM gaming_bonus_rules 
					JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
					WHERE gaming_bonus_rules.bonus_rule_id = bonusRuleID;

					IF (awardingType='CashBonus') THEN
						CALL BonusRedeemAllBonus(@bonusInstanceID, 0, -1, 'CashBonus','CashBonus', NULL);
					END IF;
				END IF;
				
				SET bonusInstanceGenID=@bonusInstanceID;
			END IF;
		ELSE 
			INSERT INTO gaming_bonus_instances_pre 
				(bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, date_created, pre_expiry_date)
			SELECT CB.bonus_rule_id, CB.client_stat_id, CB.priority, bonus_amount, wager_requirement_multiplier, CB.bonus_amount*wager_requirement_multiplier AS wager_requirement, 
			  expiry_date_fixed, expiry_days_from_awarding, NULL, NULL, NOW(), pre_expiry_date
			FROM 
			(
			  SELECT gaming_bonus_rules.priority, gaming_bonus_rules_direct_gvs_amounts.amount AS bonus_amount, expiry_date_fixed, expiry_days_from_awarding, gaming_bonus_rules.wager_requirement_multiplier, 
				gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, gaming_client_stats.currency_id, date_add(now(), interval pre_expiry_days day) as pre_expiry_date
			  FROM gaming_bonus_rules 
			  JOIN gaming_bonus_rules_direct_gvs ON 
				gaming_bonus_rules.bonus_rule_id=bonusRuleID AND 
				gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
			  JOIN gaming_client_stats ON clientStatID=gaming_client_stats.client_stat_id 
			  JOIN gaming_bonus_rules_direct_gvs_amounts ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_client_stats.currency_id 
			) AS CB 
			WHERE CB.client_stat_id NOT IN (SELECT client_stat_id FROM gaming_bonus_instances_pre WHERE gaming_bonus_instances_pre.bonus_rule_id=bonusRuleID)
			LIMIT 1;
			
			SET @bonusInstancePreID=LAST_INSERT_ID();
			SET bonusInstanceGenID=@bonusInstancePreID;
		END IF;
	ELSE
		CALL BonusAwardCWFreeRoundBonus (bonusRuleID, clientStatID, 0,IFNULL(freeRoundExpiryDate,DATE_ADD(NOW(), INTERVAL freeRoundExpiryDays DAY)),IFNULL(expiryDateFixed, DATE_ADD(NOW(), INTERVAL expiryDaysFromAwarding DAY)),  
			wagerRequirementMultiplier,numFreeRounds, balanceHistoryID, NULL, 0,0,0,0, bonusInstanceGenID, @s);
	END IF;
    
END$$

DELIMITER ;

