DROP procedure IF EXISTS `BonusCheckAwardingOnLogin`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `BonusCheckAwardingOnLogin`(sessionID BIGINT, clientStatID BIGINT, voucherCode VARCHAR(45))
root: BEGIN
  -- Added session_id in gaming_bonus_instances 
  -- Added better check for Cursor of Generic bonus bundling
  -- Better check for bonuses awarded on this login
  -- Added support of Daily bonuses
  -- Fixed free round: missing wager requirement multiplier (Daryl to Test)  
  -- Forcing indices
  -- Further optimizations with numLogins and bonusPreAuth 

 DECLARE varDone, bonusEnabledFlag, bonusLoginEnabledFlag, alreadyGivenBonus, willAwardBonusWithRuleID, bonusPreAuth,isFreeRounds TINYINT(1) DEFAULT 0;
  DECLARE clientID, sessionIDCheck, bonusRuleID, bonusRuleGetCounterID, bonusInstanceIDToAward,CWFreeRoundCounterID BIGINT DEFAULT -1;
  DECLARE awardingType VARCHAR(80);
  DECLARE numLogins INT DEFAULT 0;
 
  
  DECLARE bonusToAward CURSOR FOR
  SELECT gaming_bonus_instances.bonus_instance_id
  FROM gaming_bonus_instances FORCE INDEX (client_active_bonuses)
  JOIN gaming_bonus_rules_logins ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id
  WHERE gaming_bonus_instances.client_stat_id = clientStatID 
	AND gaming_bonus_instances.is_active=1 AND gaming_bonus_instances.extra_id = sessionID;

  DECLARE CONTINUE HANDLER FOR NOT FOUND SET varDone = TRUE;

  SELECT value_bool INTO bonusEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_ENABLED';
  SELECT value_bool INTO bonusLoginEnabledFlag FROM gaming_settings WHERE name='IS_BONUS_LOGIN_ENABLED';
  SELECT value_bool INTO bonusPreAuth FROM gaming_settings WHERE name='BONUS_PRE_AUTH';
  
  IF NOT (bonusEnabledFlag AND bonusLoginEnabledFlag) THEN
    LEAVE root;
  END IF;
  
  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  SELECT good_attempts INTO numLogins FROM gaming_clients_login_attempts_totals WHERE client_id=clientID LIMIT 1;

  CALL PlayerSelectionUpdatePlayerCacheBonus(clientStatID);
  
  SELECT session_id INTO sessionIDCheck 
  FROM sessions_main
  WHERE session_id=sessionID AND extra2_id=clientStatID  
  FOR UPDATE; 
  
  IF (sessionIDCheck<>sessionID) THEN
    LEAVE root;
  END IF;
  
  SELECT IF(COUNT(bonus_instance_id) > 0, 1, 0) INTO alreadyGivenBonus 
  FROM gaming_bonus_instances FORCE INDEX (extra_id)
  JOIN gaming_bonus_rules_logins ON gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id
  WHERE gaming_bonus_instances.client_stat_id = clientStatID AND gaming_bonus_instances.extra_id = sessionID;
  
  IF (alreadyGivenBonus) THEN
    LEAVE root;
  END IF;

  IF (bonusPreAuth=1) THEN
	  SELECT IF(COUNT(bonus_instance_pre_id) > 0, 1, 0) INTO alreadyGivenBonus 
	  FROM gaming_bonus_instances_pre FORCE INDEX (extra_id)
	  JOIN gaming_bonus_rules_logins ON gaming_bonus_instances_pre.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id
	  WHERE gaming_bonus_instances_pre.client_stat_id = clientStatID AND gaming_bonus_instances_pre.extra_id=sessionID;
	  
	  IF (alreadyGivenBonus) THEN
		LEAVE root;
	  END IF;
  END IF;
    
  SET bonusRuleID=0;

  IF(voucherCode is not null) THEN	
	SELECT bonus_rule_id INTO bonusRuleID FROM gaming_bonus_rules WHERE voucher_code=voucherCode AND restrict_by_voucher_code=1 AND is_active=1 ORDER BY bonus_rule_id DESC LIMIT 1;
  END IF;
  
  
  INSERT INTO gaming_bonus_rule_get_counter (date_added) VALUES (NOW());
  SET bonusRuleGetCounterID=LAST_INSERT_ID();
  
  SET willAwardBonusWithRuleID=0;
  
  SET @order_no=0;
  INSERT INTO gaming_bonus_rule_get_counter_rules (bonus_rule_get_counter_id, bonus_rule_id, order_no) 
  SELECT bonusRuleGetCounterID, bonus_rule_id, @order_no:=@order_no+1
  FROM
  (
    SELECT bonus_rule_id, interval_repeat_until_awarded
    FROM 
    (
      SELECT gaming_bonus_rules.priority, gaming_bonus_rules_logins_amounts.amount AS bonus_amount, gaming_bonus_rules_logins.interval_repeat_until_awarded,
        IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
        gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, 
        occurrence_num_min, occurrence_num_max, gaming_bonus_awarding_interval_types.name AS awarding_interval_type,award_bonus_max,
        CASE 
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_BONUS' THEN activation_start_date 
          WHEN gaming_bonus_awarding_interval_types.name='DAILY' THEN CURDATE()
		  WHEN gaming_bonus_awarding_interval_types.name='WEEK' THEN DateGetWeekStart()
          WHEN gaming_bonus_awarding_interval_types.name='MONTH' THEN DateGetMonthStart()
          WHEN gaming_bonus_awarding_interval_types.name='FIRST_EVER' THEN DateGetFirstEverStart()
        END AS bonus_filter_start_date, 
        (SELECT 
            (SELECT COUNT(*)
            FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
            WHERE gaming_bonus_instances.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID)
            +
            (SELECT COUNT(*)
            FROM gaming_bonus_instances_pre 
            WHERE gaming_bonus_instances_pre.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID
                  AND gaming_bonus_instances_pre.status = 1))
          AS bonuses_awarded_num, is_generic
      FROM gaming_bonus_rules 
      JOIN gaming_bonus_rules_logins ON 
        (gaming_bonus_rules.is_active AND allow_awarding_bonuses) AND 
        (NOW() BETWEEN activation_start_date AND activation_end_date) AND 
        gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
      JOIN gaming_bonus_awarding_interval_types ON gaming_bonus_rules_logins.bonus_awarding_interval_type_id=gaming_bonus_awarding_interval_types.bonus_awarding_interval_type_id
      JOIN gaming_bonus_rules_logins_amounts ON gaming_bonus_rules_logins.bonus_rule_id=gaming_bonus_rules_logins_amounts.bonus_rule_id
      LEFT JOIN gaming_bonus_rules_weekdays ON gaming_bonus_rules_logins.bonus_rule_id = gaming_bonus_rules_weekdays.bonus_rule_id AND gaming_bonus_rules_weekdays.day_no = DAYOFWEEK(NOW())
	  LEFT JOIN gaming_player_selections_player_cache AS cache FORCE INDEX (PRIMARY) ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
      JOIN gaming_client_stats ON 
        gaming_client_stats.client_stat_id=clientStatID AND gaming_bonus_rules_logins_amounts.currency_id=gaming_client_stats.currency_id AND
        IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_bonus_rules.player_selection_id,gaming_client_stats.client_stat_id)) 
      WHERE (gaming_bonus_rules.awarded_times_threshold IS NULL OR gaming_bonus_rules.awarded_times < gaming_bonus_rules.awarded_times_threshold) AND (gaming_bonus_rules_logins.restrict_weekday = 0 OR gaming_bonus_rules_weekdays.day_no IS NOT NULL)
			AND ((voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code) OR (voucherCode is null AND gaming_bonus_rules.restrict_by_voucher_code=0))
   ) AS SL
    WHERE 
    (awarding_interval_type IN ('DAILY','WEEK','MONTH') AND interval_repeat_until_awarded AND ((award_bonus_max = 0) OR (SL.bonuses_awarded_num <award_bonus_max)) AND  
    (
      
      (SL.bonuses_awarded_num < SL.occurrence_num_max) AND
      numLogins >= SL.occurrence_num_min AND 
      ( 
		IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
		FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
		WHERE (gaming_bonus_instances.bonus_rule_id=SL.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= SL.bonus_filter_start_date)),0) 
		+
		IF (bonusPreAuth=0, 0,
			IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
			FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=SL.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= SL.bonus_filter_start_date  AND gaming_bonus_instances_pre.status=1)),0) 
		)
	  )=0 
    )) OR
    (awarding_interval_type IN ('DAILY','WEEK','MONTH') AND interval_repeat_until_awarded=0 AND ((award_bonus_max = 0) OR (SL.bonuses_awarded_num <award_bonus_max)) AND  
    (
      
      (SL.bonuses_awarded_num < SL.occurrence_num_max) AND
      numLogins >= SL.occurrence_num_min AND 
      ( 
       
		IFNULL((SELECT COUNT(gaming_bonus_instances.bonus_instance_id) AS occurence_num_cur  
		FROM gaming_bonus_instances FORCE INDEX (player_rule_date)
		WHERE (gaming_bonus_instances.bonus_rule_id=SL.bonus_rule_id AND gaming_bonus_instances.client_stat_id=clientStatID AND gaming_bonus_instances.given_date >= SL.bonus_filter_start_date)),0) 
		+
		IF (bonusPreAuth=0, 0,
			IFNULL((SELECT COUNT(gaming_bonus_instances_pre.bonus_instance_pre_id) AS occurence_num_cur  
			FROM gaming_bonus_instances_pre FORCE INDEX (player_rule_date_created)
			WHERE (gaming_bonus_instances_pre.bonus_rule_id=SL.bonus_rule_id AND gaming_bonus_instances_pre.client_stat_id=clientStatID AND gaming_bonus_instances_pre.date_created >= SL.bonus_filter_start_date  AND gaming_bonus_instances_pre.status=1)),0)   
		)
      )=0 AND 
      ( 
        SELECT COUNT(extra_id) AS occurence_num_cur
        FROM sessions_main FORCE INDEX (player_date_open)
        WHERE extra2_id=SL.client_stat_id AND sessions_main.date_open >= SL.bonus_filter_start_date AND session_id<=sessionID
      )=1
    )) OR
    (awarding_interval_type IN ('FIRST_BONUS','FIRST_EVER') AND ((award_bonus_max = 0) OR (SL.bonuses_awarded_num <award_bonus_max)) AND
    (
      IF (awarding_interval_type IN ('FIRST_EVER'), numLogins,
	  ( 
        SELECT COUNT(extra_id) AS occurence_num_cur
        FROM sessions_main FORCE INDEX (player_date_open)
        WHERE extra2_id=SL.client_stat_id AND sessions_main.date_open >= SL.bonus_filter_start_date AND session_id<=sessionID
      )) BETWEEN SL.occurrence_num_min AND occurrence_num_max 
    ))
    ORDER BY is_generic, SL.priority ASC, SL.expiry_date DESC
  ) AS XX;
  
  SELECT 1, IF(bonusRuleID>0, bonusRuleID, bonus_rule_id) INTO willAwardBonusWithRuleID, bonusRuleID
  FROM gaming_bonus_rule_get_counter_rules
  WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID AND (bonusRuleID=0 OR bonus_rule_id=bonusRuleID)
  ORDER BY order_no
  LIMIT 1;
  
  
  IF(willAwardBonusWithRuleID = 0) THEN 
	LEAVE root;
  END IF;

	INSERT INTO gaming_cw_free_round_counter (timestamp) VALUES (NOW());
	
	SET CWFreeRoundCounterID = LAST_INSERT_ID();

	INSERT INTO gaming_cw_free_rounds (client_stat_id, cw_free_round_status_id, date_created, cost_per_round, free_rounds_awarded, 
		free_rounds_remaining, win_total, game_manufacturer_id, bonus_rule_id, 
		expiry_date, wager_requirement_multiplier, cw_free_round_counter_id)
	SELECT clientStatID, cw_free_round_status_id, NOW(), cost_per_round, IFNULL(gaming_bonus_rules.num_free_rounds, gaming_bonus_free_round_profiles.num_rounds),
		IFNULL(gaming_bonus_rules.num_free_rounds,gaming_bonus_free_round_profiles.num_rounds),0,gaming_bonus_free_round_profiles.game_manufacturer_id,gaming_bonus_rules.bonus_rule_id,
		IFNULL(LEAST(free_round_expiry_date, gaming_bonus_free_round_profiles.end_date), LEAST(DATE_ADD(NOW(), INTERVAL free_round_expiry_days DAY),gaming_bonus_free_round_profiles.end_date)), gaming_bonus_rules.wager_requirement_multiplier, CWFreeRoundCounterID
	FROM gaming_bonus_rule_get_counter_rules 
	JOIN gaming_bonus_rules ON 
		(gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules.bonus_rule_id = gaming_bonus_rule_get_counter_rules.bonus_rule_id)
		AND gaming_bonus_rules.is_free_rounds AND (gaming_bonus_rules.bonus_rule_id=bonusRuleID OR gaming_bonus_rules.is_generic OR (voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code)) 
	JOIN gaming_client_stats ON gaming_client_stats.client_stat_id = clientStatID
    JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id = 
				 (
					SELECT bonus_free_round_profile_id 
					FROM gaming_bonus_rule_free_round_profiles
					WHERE gaming_bonus_rule_free_round_profiles.bonus_rule_id = bonusRuleID
					LIMIT 1  #If bonus rule is linked to multiple profiles, only 1 will be used. (All of them must have same cost per spin and number of free rounds)
				  ) AND gaming_bonus_rule_free_round_profiles.bonus_rule_id = bonusRuleID
	JOIN gaming_bonus_free_round_profiles ON gaming_bonus_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id
	JOIN gaming_bonus_free_round_profiles_amounts ON gaming_bonus_free_round_profiles_amounts.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
		AND gaming_bonus_free_round_profiles_amounts.currency_id = gaming_client_stats.currency_id
	JOIN gaming_cw_free_round_statuses ON gaming_cw_free_round_statuses.name = IF(bonusPreAuth,'OnAwardedAwaitingPreAuth','OnAwarded')
	WHERE (gaming_bonus_rules.bonus_rule_id=bonusRuleID OR gaming_bonus_rules.is_generic OR (voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code)) AND is_free_rounds = 1
	LIMIT 1; #If bonus rule is linked to multiple profiles, only 1 will be used. (All of them must have same cost per spin and number of free rounds)
  
  IF (bonusPreAuth=0) THEN
    
    INSERT INTO gaming_bonus_instances 
      (priority, bonus_amount_given, bonus_amount_remaining, bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, bonus_rule_id, client_stat_id, extra_id, transfer_every_x, transfer_every_amount, session_id,cw_free_round_id,is_free_rounds,is_free_rounds_mode)
    SELECT priority, bonus_amount, bonus_amount, bonus_amount*wager_requirement_multiplier, bonus_amount*wager_requirement_multiplier, NOW(), expiry_date, bonus_rule_id, client_stat_id, sessionID, transfer_every_x, transfer_every_amount, sessionID,cw_free_round_id,IF(cw_free_round_id IS NULL,0,1),IF(cw_free_round_id IS NULL,0,1)
    FROM 
    (
      SELECT gaming_bonus_rules.priority, IF(gaming_bonus_rules.is_free_rounds=0,gaming_bonus_rules_logins_amounts.amount,0) AS bonus_amount,
        IFNULL(expiry_date_fixed, DATE_ADD(NOW(), INTERVAL expiry_days_from_awarding DAY)) AS expiry_date, 
        gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, 
        occurrence_num_min, occurrence_num_max,
        CASE gaming_bonus_types_release.name
          WHEN 'EveryXWager' THEN gaming_bonus_rules.transfer_every_x_wager
          WHEN 'EveryReleaseAmount' THEN IF(gaming_bonus_rules.is_free_rounds=0,ROUND(gaming_bonus_rules.wager_requirement_multiplier/(gaming_bonus_rules_logins_amounts.amount/wager_restrictions.release_every_amount),2),0)
          ELSE NULL
        END AS transfer_every_x, 
        CASE gaming_bonus_types_release.name
          WHEN 'EveryXWager' THEN IF(gaming_bonus_rules.is_free_rounds=0,ROUND(gaming_bonus_rules_logins_amounts.amount/(gaming_bonus_rules.wager_requirement_multiplier/gaming_bonus_rules.transfer_every_x_wager), 0),0)
          WHEN 'EveryReleaseAmount' THEN wager_restrictions.release_every_amount
          ELSE NULL
        END AS transfer_every_amount,cw_free_round_id
      FROM gaming_bonus_rule_get_counter_rules 
	  JOIN gaming_bonus_rules ON 
		(gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules.bonus_rule_id = gaming_bonus_rule_get_counter_rules.bonus_rule_id)
		AND (gaming_bonus_rules.bonus_rule_id=bonusRuleID OR gaming_bonus_rules.is_generic OR (voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code)) 
      JOIN gaming_bonus_rules_logins ON gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id 
      JOIN gaming_bonus_rules_logins_amounts ON gaming_bonus_rules_logins.bonus_rule_id=gaming_bonus_rules_logins_amounts.bonus_rule_id 
      JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_bonus_rules_logins_amounts.currency_id=gaming_client_stats.currency_id 
	  LEFT JOIN gaming_bonus_types_transfers ON gaming_bonus_rules.bonus_type_transfer_id=gaming_bonus_types_transfers.bonus_type_transfer_id
      LEFT JOIN gaming_bonus_types_release ON gaming_bonus_rules.bonus_type_release_id=gaming_bonus_types_release.bonus_type_release_id
      LEFT JOIN gaming_bonus_rules_wager_restrictions AS wager_restrictions ON wager_restrictions.bonus_rule_id=gaming_bonus_rules.bonus_rule_id AND wager_restrictions.currency_id=gaming_client_stats.currency_id
	  LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND cw_free_round_counter_id=CWFreeRoundCounterID
	) AS SL;
    
    
    SET @rowCount=ROW_COUNT();
    
    IF (@rowCount>0) THEN
	  OPEN bonusToAward;
	  curser_loop: LOOP
		SET varDone=0;

		FETCH bonusToAward INTO bonusInstanceIDToAward;		
		IF varDone THEN
		  LEAVE curser_loop;
		END IF;

		  CALL BonusOnAwardedUpdateStats(bonusInstanceIDToAward);

			SELECT gaming_bonus_types_awarding.name,gaming_bonus_rules.is_free_rounds INTO awardingType, isFreeRounds
			FROM gaming_bonus_instances
			JOIN gaming_bonus_rules ON gaming_bonus_rules.bonus_rule_id = gaming_bonus_instances.bonus_rule_id
			JOIN gaming_bonus_types_awarding ON gaming_bonus_types_awarding.bonus_type_awarding_id = gaming_bonus_rules.bonus_type_awarding_id
			WHERE gaming_bonus_instances.bonus_instance_id = bonusInstanceIDToAward;

			IF (awardingType='CashBonus' AND isFreeRounds =0) THEN
				CALL BonusRedeemAllBonus(bonusInstanceIDToAward, sessionID, -1, 'CashBonus','CashBonus', NULL);
			END IF;
	  END LOOP;
	  CLOSE bonusToAward;
    END IF;
    
  ELSE 

    INSERT INTO gaming_bonus_instances_pre 
      (bonus_rule_id, client_stat_id, priority, bonus_amount, wager_requirement_multiplier, wager_requirement, expiry_date_fixed, expiry_days_from_awarding, extra_id, session_id, date_created, pre_expiry_date,cw_free_round_id)
    SELECT SL.bonus_rule_id, SL.client_stat_id, SL.priority, IF(is_free_rounds=0,bonus_amount,0), wager_requirement_multiplier, IF(is_free_rounds=0,bonus_amount,0)*wager_requirement_multiplier AS wager_requirement,
      expiry_date_fixed, expiry_days_from_awarding, sessionID, sessionID, NOW(), pre_expiry_date, cw_free_round_id
    FROM 
    (
      SELECT gaming_bonus_rules.priority, gaming_bonus_rules_logins_amounts.amount AS bonus_amount, expiry_date_fixed, expiry_days_from_awarding,
        gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_rules.bonus_rule_id, gaming_client_stats.client_stat_id, date_add(now(), interval pre_expiry_days day) as pre_expiry_date,cw_free_round_id, gaming_bonus_rules.is_free_rounds
	  FROM gaming_bonus_rule_get_counter_rules 
	  JOIN gaming_bonus_rules ON 
		(gaming_bonus_rule_get_counter_rules.bonus_rule_get_counter_id=bonusRuleGetCounterID AND gaming_bonus_rules.bonus_rule_id = gaming_bonus_rule_get_counter_rules.bonus_rule_id)
		AND (gaming_bonus_rules.bonus_rule_id=bonusRuleID OR gaming_bonus_rules.is_generic OR (voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code)) 
	  JOIN gaming_bonus_rules_logins ON (gaming_bonus_rules.bonus_rule_id=bonusRuleID OR gaming_bonus_rules.is_generic OR (voucherCode is not null AND voucherCode=gaming_bonus_rules.voucher_code)) AND gaming_bonus_rules.bonus_rule_id=gaming_bonus_rules_logins.bonus_rule_id
      JOIN gaming_bonus_rules_logins_amounts ON gaming_bonus_rules_logins.bonus_rule_id=gaming_bonus_rules_logins_amounts.bonus_rule_id 
      JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gaming_bonus_rules_logins_amounts.currency_id=gaming_client_stats.currency_id 
      LEFT JOIN gaming_cw_free_rounds ON gaming_cw_free_rounds.bonus_rule_id = gaming_bonus_rules.bonus_rule_id AND cw_free_round_counter_id=CWFreeRoundCounterID
    ) AS SL; 
    
  END IF;

  DELETE FROM gaming_bonus_rule_get_counter_rules WHERE bonus_rule_get_counter_id=bonusRuleGetCounterID;
END root$$

DELIMITER ;

