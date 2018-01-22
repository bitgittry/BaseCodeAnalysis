DROP procedure IF EXISTS `CommonWalletGetBalanceWithGameID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CommonWalletGetBalanceWithGameID`(clientStatID BIGINT, gameID BIGINT)
BEGIN

	DECLARE operatorGameID, gameManufacturerID BIGINT DEFAULT -1;
	DECLARE freeRoundEnabled, cwFreeRoundEnabled TINYINT(1) DEFAULT 0;
	DECLARE applicableBon TINYINT(1) DEFAULT 0;
	DECLARE playWagerType VARCHAR(80);

	SELECT value_bool INTO freeRoundEnabled FROM gaming_settings WHERE name='IS_BONUS_FREE_ROUND_ENABLED';
	SELECT value_bool INTO cwFreeRoundEnabled FROM gaming_settings WHERE name='IS_BONUS_CW_FREE_ROUND_ENABLED';

	SELECT gaming_game_manufacturers.game_manufacturer_id, gaming_operator_games.operator_game_id
	INTO gameManufacturerID, operatorGameID
	FROM gaming_game_manufacturers
	JOIN gaming_games ON gaming_games.game_id=gameID AND gaming_game_manufacturers.game_manufacturer_id=gaming_games.game_manufacturer_id
	JOIN gaming_operators ON gaming_operators.is_main_operator=1
	JOIN gaming_operator_games ON gaming_operator_games.operator_id=gaming_operators.operator_id AND gaming_games.game_id=gaming_operator_games.game_id;

  	SELECT value_string INTO playWagerType FROM gaming_settings WHERE name = 'PLAY_WAGER_TYPE';
  
	IF (playWagerType = 'Type2') THEN
		SELECT 1 INTO applicableBon
		FROM
			(SELECT gbi.bonus_rule_id 
			FROM gaming_bonus_instances AS gbi
			WHERE (gbi.client_stat_id=clientStatID AND gbi.is_active AND gbi.is_free_rounds_mode=0)
			ORDER BY gbi.given_date ASC,gbi.bonus_instance_id ASC
			LIMIT 1 ) AS gbi
		JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
		;
        
	END IF;

	SELECT current_real_balance + IFNULL(Bonuses.current_bonus_balance + Bonuses.current_bonus_win_locked_balance,0) + 
		IF(cw_freerounds_addtobonus,
			IFNULL(FreeRounds.free_rounds_balance,0),
		  0) AS current_balance, current_real_balance, 
		IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance,0)+IF(cw_freerounds_addtobonus, IFNULL(FreeRounds.free_rounds_balance, 0), 0) AS current_bonus_balance, pl_currency.currency_code,
		ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
		current_ring_fenced_amount,current_ring_fenced_sb,current_ring_fenced_casino,current_ring_fenced_poker,
		IFNULL(CWFreeRounds.cw_free_rounds_balance,0) AS current_cw_free_rounds_balance
	FROM gaming_client_stats FORCE INDEX (PRIMARY)  
	JOIN gaming_currency AS pl_currency ON client_stat_id=clientStatID AND gaming_client_stats.currency_id=pl_currency.currency_id
	JOIN gaming_operators ON gaming_operators.is_main_operator=1
	JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id = gameManufacturerID
	JOIN gaming_games ON gaming_games.game_id=gameID AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
	LEFT JOIN gaming_currency ON gaming_currency.currency_code=gaming_game_manufacturers.cw_exchange_currency
	LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gaming_currency.currency_id=gm_exchange_rate.currency_id 
	LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_client_stats.currency_id 
	LEFT JOIN
	(
		SELECT SUM(num_rounds_remaining * gbrfra.max_bet) AS free_rounds_balance 
		FROM gaming_bonus_free_rounds AS gbfr FORCE INDEX (client_stat_id)
		JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gbfr.client_stat_id=gaming_client_stats.client_stat_id AND gbfr.is_active
		JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_client_stats.currency_id
		JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbfr.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
	) AS FreeRounds ON 1=1
	LEFT JOIN
	(
		SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
		FROM gaming_bonus_instances AS gbi
		JOIN gaming_bonus_rules AS gbr ON gbi.bonus_rule_id=gbr.bonus_rule_id
		JOIN gaming_bonus_types_awarding AS gbta ON gbr.bonus_type_awarding_id=gbta.bonus_type_awarding_id
		JOIN gaming_bonus_types ON gbr.bonus_type_id=gaming_bonus_types.bonus_type_id
		LEFT JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
		WHERE gbi.client_stat_id=clientStatID AND gbi.is_active AND 
		((playWagerType = 'Type1' AND gbrwrw.bonus_rule_id IS NOT NULL) OR (playWagerType = 'Type2' AND applicableBon))
	) AS Bonuses ON 1=1
	LEFT JOIN
	(
		SELECT SUM(IFNULL(gcwfr.free_rounds_remaining * gcwfr.cost_per_round,0)) AS cw_free_rounds_balance 
		FROM gaming_cw_free_round_statuses AS gcwfrs
		JOIN gaming_cw_free_rounds AS gcwfr FORCE INDEX (player_with_status) ON
			gcwfrs.name NOT IN ('FinishedAndTransfered','Forfeited','Expired')	
			AND (gcwfr.client_stat_id = clientStatID AND gcwfr.cw_free_round_status_id = gcwfrs.cw_free_round_status_id)			
		JOIN gaming_bonus_instances ON gaming_bonus_instances.cw_free_round_id = gcwfr.cw_free_round_id
		JOIN gaming_bonus_rules ON gaming_bonus_instances.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
        JOIN gaming_bonus_rule_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_rule_id = gaming_bonus_rules.bonus_rule_id
		JOIN gaming_bonus_free_round_profiles ON gaming_bonus_rule_free_round_profiles.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id 
			AND gaming_bonus_free_round_profiles.is_active = 1 AND gaming_bonus_free_round_profiles.is_hidden = 0		
		JOIN gaming_bonus_free_round_profiles_games ON gaming_bonus_free_round_profiles_games.bonus_free_round_profile_id = gaming_bonus_free_round_profiles.bonus_free_round_profile_id
			AND gaming_bonus_free_round_profiles_games.game_id = gameID		
	) AS CWFreeRounds ON 1=1;


	IF (freeRoundEnabled) THEN
		SELECT bonus_free_round_id, priority, num_rounds_given, num_rounds_remaining, total_amount_won, bonus_transfered_total, given_date, expiry_date, lost_date, used_all_date, 
			is_lost, is_used_all, gbfr.is_active, gbfr.bonus_rule_id, gbfr.client_stat_id, gbrfra.min_bet, gbrfra.max_bet  
		FROM gaming_bonus_free_rounds AS gbfr FORCE INDEX (client_stat_id)
		JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=clientStatID AND gbfr.client_stat_id=gaming_client_stats.client_stat_id AND gbfr.is_active
		JOIN gaming_bonus_rules_free_rounds_amounts AS gbrfra ON gbfr.bonus_rule_id=gbrfra.bonus_rule_id AND gbrfra.currency_id=gaming_client_stats.currency_id
		JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbfr.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
		ORDER BY given_date DESC;
	END IF;

END$$

DELIMITER ;

