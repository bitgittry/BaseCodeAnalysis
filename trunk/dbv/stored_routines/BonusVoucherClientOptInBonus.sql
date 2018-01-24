DROP procedure IF EXISTS `BonusVoucherClientOptInBonus`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusVoucherClientOptInBonus`(clientStatID BIGINT, sessionID BIGINT, voucherCode VARCHAR(255), OUT statusCode INT)
root: BEGIN
  
  -- Checking whether there are any direct give bonuses to award 

  DECLARE rowCount, bonusRuleAwardCounterID BIGINT DEFAULT -1;
  DECLARE playerSelectionID, clientID, voucherID, voucherIDGiven BIGINT DEFAULT -1;
  DECLARE isInSelection, bonusPreAuth TINYINT(1);
  DECLARE currentDate, activationDate, deactivationDate DATETIME DEFAULT NOW();
  DECLARE numVouchersMatched, numDirectBonues, isActive BIGINT DEFAULT 0;
	

  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
	
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;	

  SELECT COUNT(*) INTO numVouchersMatched
  FROM gaming_vouchers 
  WHERE voucher_code=voucherCode AND is_active=1 AND is_deleted=0;

  SELECT voucher_id, player_selection_id, activation_date, deactivation_date 
  INTO voucherID, playerSelectionID, activationDate, deactivationDate
  FROM gaming_vouchers 
  WHERE voucher_code=voucherCode AND is_active=1 AND is_deleted=0 AND (numVouchersMatched<=1 OR NOW() BETWEEN activation_date AND deactivation_date) 
  ORDER BY voucher_id DESC LIMIT 1;

  IF (voucherID = -1) THEN
	SELECT is_active INTO isActive
    FROM gaming_vouchers
    WHERE voucher_code=voucherCode AND is_deleted=0 AND (numVouchersMatched<=1 OR NOW() BETWEEN activation_date AND deactivation_date) 
	ORDER BY voucher_id DESC LIMIT 1;
    
    IF (isActive = 0) THEN
		# Voucher is not active
		SET statusCode=4;
		LEAVE root;
    ELSE
		# Voucher is not valid or expired
		SET statusCode=1;
		LEAVE root;
    END IF;
  END IF;

  IF (activationDate > NOW()) THEN
	SET statusCode=4;
	LEAVE root;
  END IF;

  IF (deactivationDate < NOW()) THEN
	SET statusCode=5;
	LEAVE root;
  END IF;

  SELECT COUNT(*) as given_num INTO voucherIDGiven FROM gaming_voucher_instances WHERE voucher_id=voucherID AND client_stat_id=clientStatID;
  
  IF (voucherIDGiven>0) THEN
	SET statusCode=2;
	LEAVE root;
  END IF;

  SELECT PlayerSelectionIsPlayerInSelection(playerSelectionID, clientStatID) INTO isInSelection;

  IF (isInSelection=0) THEN
	SET statusCode=3;
	LEAVE root;
  END IF;

  INSERT INTO gaming_voucher_instances (voucher_id, client_stat_id, given_date) VALUES (voucherID, clientStatID, NOW());
  
  INSERT INTO gaming_player_selections_selected_players (player_selection_id, client_stat_id, include_flag, exclude_flag) 
  SELECT gbr.player_selection_id, clientStatID, 1, 0 
  FROM gaming_voucher_bonuses AS gvb
  JOIN gaming_bonus_rules AS gbr ON (gvb.bonus_rule_id = gbr.bonus_rule_id AND gbr.activation_end_date > currentDate
		AND gbr.is_hidden=0 AND gbr.is_manual_bonus=0 AND ((gbr.is_active=1 AND gbr.bonus_type_id IN (2,3,5)) OR gbr.bonus_type_id = 1))
  WHERE gvb.voucher_id=voucherID
  ON DUPLICATE KEY UPDATE client_stat_id=clientStatID;
  
  
  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date)
  SELECT gbr.player_selection_id, 
		 clientStatID, 
		 1, 
		 DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gbr.player_selection_id)  MINUTE)
  FROM gaming_voucher_bonuses AS gvb
  JOIN gaming_bonus_rules AS gbr ON (gvb.bonus_rule_id = gbr.bonus_rule_id AND gbr.activation_end_date > currentDate
	   AND gbr.is_manual_bonus=0 AND ((gbr.is_active=1 AND gbr.bonus_type_id IN (2,3,5)) OR gbr.bonus_type_id = 1))
  WHERE gvb.voucher_id=voucherID
  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
				  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
				  gaming_player_selections_player_cache.last_updated=NOW();
  
  UPDATE gaming_player_selections gpsel
  JOIN gaming_bonus_rules AS gbr ON (gbr.player_selection_id=gpsel.player_selection_id AND gbr.activation_end_date > currentDate 
	   AND gbr.is_manual_bonus=0 AND ((gbr.is_active=1 AND gbr.bonus_type_id IN (2,3,5)) OR gbr.bonus_type_id = 1))
  JOIN gaming_voucher_bonuses AS gvb ON (gvb.voucher_id=voucherID AND gvb.bonus_rule_id = gbr.bonus_rule_id)
  SET gpsel.selected_players=1
  WHERE gpsel.selected_players=0;

  IF (sessionID > 0) THEN
     CALL BonusCheckAwardingOnLogin(sessionID, clientStatID, NULL);  
  END IF;

  SELECT COUNT(*) INTO numDirectBonues
  FROM gaming_voucher_bonuses AS gvb 
  JOIN gaming_bonus_rules AS gbr ON (gvb.bonus_rule_id = gbr.bonus_rule_id AND activation_end_date > NOW() AND gbr.bonus_type_id = 1) 
  WHERE gvb.voucher_id = voucherID;

  IF (numDirectBonues>0) THEN

    INSERT INTO gaming_bonus_rule_award_counter(bonus_rule_id, date_created)
    SELECT -1, NOW();
  
    SET bonusRuleAwardCounterID=LAST_INSERT_ID();

    IF (bonusPreAuth=0) THEN

	  INSERT INTO gaming_bonus_instances (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, bonus_rule_award_counter_id, transfer_every_x, transfer_every_amount) 
	  SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, currentDate, expiry_date, bonus_rule_id, client_stat_id, bonusRuleAwardCounterID, transfer_every_x, transfer_every_amount 
	  FROM
	  (
		
		  SELECT priority, bonus_amount, wager_requirement_multiplier, expiry_date, bonus_rule_id, client_stat_id, transfer_every_x, transfer_every_amount 
		  FROM
		  (
			SELECT gbr.priority, gaming_bonus_rules_direct_gvs_amounts.amount AS bonus_amount, 
			  IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
			  gbr.wager_requirement_multiplier, gbr.bonus_rule_id, clientStatID as client_stat_id,
			  CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN gbr.transfer_every_x_wager
				WHEN 'EveryReleaseAmount' THEN ROUND(gbr.wager_requirement_multiplier/(gaming_bonus_rules_direct_gvs_amounts.amount/wager_restrictions.release_every_amount),2)
				ELSE NULL
			  END AS transfer_every_x, 
			  CASE gaming_bonus_types_release.name
				WHEN 'EveryXWager' THEN ROUND(gaming_bonus_rules_direct_gvs_amounts.amount/(gbr.wager_requirement_multiplier/gbr.transfer_every_x_wager), 0)
				WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
				ELSE NULL
			  END AS transfer_every_amount
			FROM gaming_voucher_bonuses AS gvb 
			JOIN gaming_bonus_rules AS gbr ON (gvb.bonus_rule_id = gbr.bonus_rule_id AND 
					activation_end_date > NOW() AND gbr.bonus_type_id = 1) 
			JOIN gaming_bonus_rules_direct_gvs ON gbr.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id
			JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
			JOIN gaming_bonus_rules_direct_gvs_amounts ON gbr.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_client_stats.currency_id 
			LEFT JOIN gaming_bonus_types_transfers ON gbr.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
			LEFT JOIN gaming_bonus_types_release ON gbr.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
			LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gbr.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
			WHERE gvb.voucher_id = voucherID
		  ) AS CB
		  WHERE NOT EXISTS (SELECT bonus_instance_id FROM gaming_bonus_instances WHERE gaming_bonus_instances.bonus_rule_id=CB.bonus_rule_id AND gaming_bonus_instances.client_stat_id=CB.client_stat_id)
	  ) as xx;

	  SET rowCount=ROW_COUNT();

	  IF (rowCount > 0) THEN
		CALL BonusOnAwardedUpdateStatsMultipleBonuses(bonusRuleAwardCounterID, 1);
	  END IF;
      
    ELSE
		
        INSERT INTO gaming_bonus_instances_pre 
			(bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, date_created)
		SELECT CB.bonus_rule_id, CB.client_stat_id, CB.priority, bonus_amount, wager_requirement_multiplier, CB.bonus_amount*wager_requirement_multiplier AS wager_requirement, 
		  expiry_date_fixed, expiry_days_from_awarding, NULL, NULL, NOW()
		FROM 
		(
		  SELECT gbr.priority, gaming_bonus_rules_direct_gvs_amounts.amount AS bonus_amount, expiry_date_fixed, expiry_days_from_awarding, gbr.wager_requirement_multiplier, 
			gbr.bonus_rule_id, gaming_client_stats.client_stat_id, gaming_client_stats.currency_id
		  FROM gaming_voucher_bonuses AS gvb 
		  JOIN gaming_bonus_rules AS gbr ON (gvb.bonus_rule_id = gbr.bonus_rule_id AND
			activation_end_date > NOW() AND gbr.bonus_type_id = 1) 
		  JOIN gaming_bonus_rules_direct_gvs ON gbr.bonus_rule_id=gaming_bonus_rules_direct_gvs.bonus_rule_id 
		  JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID
		  JOIN gaming_bonus_rules_direct_gvs_amounts ON gbr.bonus_rule_id=gaming_bonus_rules_direct_gvs_amounts.bonus_rule_id AND gaming_bonus_rules_direct_gvs_amounts.currency_id=gaming_client_stats.currency_id 
		  WHERE gvb.voucher_id = voucherID
		) AS CB 
		WHERE NOT EXISTS 
        (
			SELECT bonus_instance_pre_id 
            FROM gaming_bonus_instances_pre 
            WHERE gaming_bonus_instances_pre.bonus_rule_id=CB.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=CB.client_stat_id
		);
        
    END IF; -- bonusPreAuth=0

  END IF; -- @numDirectBonues>0

  SET statusCode=0;
END root$$

DELIMITER ;

