DROP procedure IF EXISTS `GameSessionGetStats`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionGetStats`(clientStatID BIGINT, operatorGameID BIGINT, sessionID BIGINT)
BEGIN
  -- update tournament feed
  DECLARE clientID, currencyID, gameID BIGINT DEFAULT -1;
  DECLARE bonusEnabledFlag, promotionEnabled, tournamentsEnabled, fraudEnabled, playConstraintsEnabled, playLimitEnabled TINYINT(1) DEFAULT 0;
  
  SELECT client_id, currency_id INTO clientID, currencyID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  SELECT game_id INTO gameID FROM gaming_operator_games WHERE operator_game_id=operatorGameID;
  
  SELECT gs1.value_bool as vb1, gs2.value_bool as vb2, gs3.value_bool as vb3, gs4.value_bool as vb4, gs5.value_bool as vb5, gs6.value_bool as vb6
  INTO bonusEnabledFlag, promotionEnabled, tournamentsEnabled, fraudEnabled, playConstraintsEnabled, playLimitEnabled
  FROM gaming_settings gs1 
  JOIN gaming_settings gs2 ON (gs2.name='IS_PROMOTION_ENABLED')
  JOIN gaming_settings gs3 ON (gs3.name='IS_TOURNAMENTS_ENABLED')
  JOIN gaming_settings gs4 ON (gs4.name='FRAUD_ENABLED')
  JOIN gaming_settings gs5 ON (gs5.name='PLAY_CONSTRAINTS_ENABLED')
  JOIN gaming_settings gs6 ON (gs6.name='PLAY_LIMIT_ENABLED')
  WHERE gs1.name='IS_BONUS_ENABLED';
  
  IF (bonusEnabledFlag) THEN
    SELECT bonus_instance_id, gbi.priority, bonus_amount_given, bonus_amount_remaining, total_amount_won, current_win_locked_amount, 
      bonus_wager_requirement, bonus_wager_requirement_remain, given_date, expiry_date, secured_date, lost_date, used_all_date, 
      is_secured, is_lost, is_used_all, gbi.is_active, 
	  gbi.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gaming_bonus_rules.wager_requirement_multiplier, gaming_bonus_types.name AS bonus_type, client_stat_id, gbi.extra_id, 
      bonus_transfered_total, transfer_every_x, transfer_every_amount, transfer_every_x_last, NULL AS reason, current_ring_fenced_amount, gaming_bonus_rules.is_generic,
	  gbi.is_free_rounds,gbi.is_free_rounds_mode,gbi.cw_free_round_id
    FROM gaming_bonus_instances AS gbi 
    JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.client_stat_id=clientStatID AND gbi.is_active) AND
      (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
    JOIN gaming_bonus_rules ON gbi.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
    JOIN gaming_bonus_types ON gaming_bonus_rules.bonus_type_id = gaming_bonus_types.bonus_type_id
    LEFT JOIN sessions_main ON sessions_main.session_id=sessionID
    LEFT JOIN gaming_bonus_rules_platform_types AS platform_types ON gaming_bonus_rules.bonus_rule_id=platform_types.bonus_rule_id AND sessions_main.platform_type_id=platform_types.platform_type_id
    WHERE (gaming_bonus_rules.restrict_platform_type=0 OR platform_types.platform_type_id IS NOT NULL)
    ORDER BY gbi.priority ASC, gbi.given_date ASC;
    
    SELECT bonus_free_round_id, gbfr.priority, gbfr.num_rounds_given, gbfr.num_rounds_remaining, gbfr.total_amount_won, gbfr.bonus_transfered_total, gbfr.given_date, gbfr.expiry_date, gbfr.lost_date, gbfr.used_all_date, 
      gbfr.is_lost, gbfr.is_used_all, gbfr.is_active, gbfr.bonus_rule_id, gaming_bonus_rules.name AS bonus_name, gbfr.client_stat_id, gbrfra.min_bet, gbrfra.max_bet  
    FROM gaming_bonus_free_rounds AS gbfr
    JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=currencyID
    JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbfr.client_stat_id=clientStatID AND gbfr.is_active) AND
      (gbfr.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
    JOIN gaming_bonus_rules ON gbfr.bonus_rule_id=gaming_bonus_rules.bonus_rule_id
    LEFT JOIN sessions_main ON sessions_main.session_id=sessionID
    LEFT JOIN gaming_bonus_rules_platform_types AS platform_types ON gaming_bonus_rules.bonus_rule_id=platform_types.bonus_rule_id AND sessions_main.platform_type_id=platform_types.platform_type_id
    WHERE (gbfr.client_stat_id=clientStatID AND gbfr.is_active=1) AND (gaming_bonus_rules.restrict_platform_type=0 OR platform_types.platform_type_id IS NOT NULL)
    ORDER BY gbfr.priority ASC, gbfr.given_date ASC;
  ELSE
    SELECT NULL;
	SELECT NULL;
  END IF;
  
  IF (promotionEnabled) THEN
    CALL PromotionGetAllPlayerPromotionStatusFilterByDateType('CURRENT', clientStatID, currencyID, 1, operatorGameID, NULL);
  ELSE
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
    SELECT NULL;
	SELECT NULL;
	SELECT NULL;
  END IF;
  
  IF (tournamentsEnabled) THEN
    SELECT tournament_player_status_id, gaming_tournaments.tournament_id, gaming_tournaments.name AS tournament_name, player_statuses.total_bet, player_statuses.total_win, player_statuses.rounds, player_statuses.score, player_statuses.rank, opted_in_date, player_statuses.is_active, player_statuses.priority,
       gaming_tournaments.tournament_date_start AS tournament_start_date,  gaming_tournaments.tournament_date_end AS tournament_end_date, gaming_tournaments.tournament_date_end<NOW() AS has_expired
	   , player_statuses.last_updated_date, player_statuses.previous_rank, gaming_tournaments.last_temp_rank_update_date
    FROM gaming_tournament_player_statuses AS player_statuses  
    JOIN gaming_tournaments ON player_statuses.tournament_id=gaming_tournaments.tournament_id AND gaming_tournaments.tournament_date_start<NOW() AND gaming_tournaments.tournament_date_end>NOW()
    JOIN gaming_tournament_games ON gaming_tournaments.tournament_id=gaming_tournament_games.tournament_id AND gaming_tournament_games.game_id=gameID
    WHERE player_statuses.client_stat_id=clientStatID AND player_statuses.is_active;
  ELSE
    SELECT NULL;
  END IF;
  
  IF (fraudEnabled) THEN
    SELECT 
      fraud_client_event_id, fraud_event_type_id, extra_id, rule_points, override_points, fraud_classification_type_id, event_date, is_current  
    FROM gaming_fraud_client_events
    WHERE gaming_fraud_client_events.client_stat_id=clientStatID AND is_current=1;

    SELECT classification_types.fraud_classification_type_id, name, description, safety_level, points_min_range, points_max_range, colour,  
      disallow_login, disallow_transfers, disallow_play, kickout, is_active
    FROM gaming_fraud_classification_types AS classification_types
    JOIN gaming_fraud_client_events ON 
      gaming_fraud_client_events.client_stat_id=clientStatID AND is_current=1 AND
      classification_types.fraud_classification_type_id=gaming_fraud_client_events.fraud_classification_type_id;
  ELSE
    SELECT NULL;
    SELECT NULL;
  END IF;
  
  IF (playConstraintsEnabled) THEN
    SELECT NULL;
  ELSE
    SELECT NULL;
  END IF;
  

  IF (playLimitEnabled) THEN
    SELECT PlayLimitCheckExceeded(0, sessionID, clientStatID, 'casino') AS limit_exceeded;
  ELSE
    SELECT FALSE;
  END IF;


END$$

DELIMITER ;

