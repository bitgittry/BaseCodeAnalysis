DROP procedure IF EXISTS `PlayerGiveBulkBonusUpdateData`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerGiveBulkBonusUpdateData`(clientStatID BIGINT, bonusBulkPlayerID BIGINT, varAmount DECIMAL(18,5), wageringReqMult DECIMAL(18,5), expireyDateFixed DATETIME, expireyDaysFromAwarding INT, varReason MEDIUMTEXT )
BEGIN
	-- optimized by using player selection cache 
	
	DECLARE bonusRuleIDCheck, playerSelectionID BIGINT DEFAULT -1;

	SELECT gaming_bonus_rules.bonus_rule_id,player_selection_id INTO bonusRuleIDCheck,playerSelectionID
	FROM gaming_bonus_bulk_players
	JOIN gaming_bonus_bulk_counter ON gaming_bonus_bulk_counter.bonus_bulk_counter_id = gaming_bonus_bulk_players.bonus_bulk_counter_id
	JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id= gaming_bonus_bulk_counter.bonus_rule_id
	JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	WHERE bonus_bulk_player_id = bonusBulkPlayerID LIMIT 1;

	UPDATE gaming_bonus_bulk_players
	SET amount = varAmount, wagering_requirment_multiplier=wageringReqMult, expirey_date = expireyDateFixed, expirey_days_from_awarding=expireyDaysFromAwarding,
		reason=varReason,client_stat_id = clientStatID, is_invalid=1
	WHERE bonus_bulk_player_id = bonusBulkPlayerID;

	UPDATE gaming_bonus_bulk_players
	LEFT JOIN gaming_client_stats ON gaming_bonus_bulk_players.client_stat_id = gaming_client_stats.client_stat_id
	LEFT JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = bonusRuleIDCheck
	LEFT JOIN gaming_bonus_rules_manuals ON gaming_bonus_rules_manuals.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
	LEFT JOIN gaming_bonus_rules_manuals_amounts ON gaming_bonus_rules_manuals.bonus_rule_id = gaming_bonus_rules_manuals_amounts.bonus_rule_id AND gaming_client_stats.currency_id = gaming_bonus_rules_manuals_amounts.currency_id
	LEFT JOIN gaming_player_selections_player_cache AS selected_players ON selected_players.player_selection_id=playerSelectionID AND selected_players.client_stat_id=clientStatID AND selected_players.player_in_selection=1 
		SET 
		invalid_wager = IF (gaming_bonus_bulk_players.wagering_requirment_multiplier BETWEEN gaming_bonus_rules_manuals.min_wager_requirement_multiplier AND gaming_bonus_rules_manuals.max_wager_requirement_multiplier,0,1),
		invalid_amount = IF (gaming_bonus_bulk_players.amount BETWEEN gaming_bonus_rules_manuals_amounts.min_amount AND gaming_bonus_rules_manuals_amounts.max_amount,0,1),
		invalid_expiry = IF (
				(
					(
						gaming_bonus_bulk_players.expirey_days_from_awarding IS NOT NULL AND 
						 IF(gaming_bonus_rules_manuals.min_expiry_days_from_awarding IS NOT NULL,
								gaming_bonus_bulk_players.expirey_days_from_awarding BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding,
								DATE_ADD(NOW(), INTERVAL gaming_bonus_bulk_players.expirey_days_from_awarding DAY) BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed
							)
					) 
					OR 
					(
						gaming_bonus_bulk_players.expirey_date IS NOT NULL AND
						IF(gaming_bonus_rules_manuals.min_expiry_date_fixed IS NOT NULL,
							gaming_bonus_bulk_players.expirey_date BETWEEN gaming_bonus_rules_manuals.min_expiry_date_fixed AND gaming_bonus_rules_manuals.max_expiry_date_fixed,
							DATEDIFF(gaming_bonus_bulk_players.expirey_date ,NOW()) BETWEEN gaming_bonus_rules_manuals.min_expiry_days_from_awarding AND gaming_bonus_rules_manuals.max_expiry_days_from_awarding
						   )
					)
				) ,0,1),
		invalid_client = IF (gaming_client_stats.client_stat_id IS NULL,1,0),
		not_in_bonus_selection = IF (selected_players.client_stat_id IS NULL,1,0)
	WHERE bonus_bulk_player_id = bonusBulkPlayerID AND is_given=0 ;

	UPDATE gaming_bonus_bulk_players
	SET is_invalid =0
	WHERE bonus_bulk_player_id = bonusBulkPlayerID  AND not_in_bonus_selection=0 AND invalid_client=0 AND invalid_expiry=0 AND invalid_amount = 0 AND invalid_wager =0;
END$$

DELIMITER ;

