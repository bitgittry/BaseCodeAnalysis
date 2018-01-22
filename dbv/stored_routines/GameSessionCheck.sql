DROP procedure IF EXISTS `GameSessionCheck`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameSessionCheck`(gameSessionKey VARCHAR(80), componentID BIGINT, ignoreSessionExpiry TINYINT(1), extendSessionExpiry TINYINT(1), OUT statusCode INT)
root:BEGIN

  /*Status code
  0 - Success
  1 - CheckInvalid or Expired Session, Or User is blocked 
  2 - Client Stat Account Blocked Account
  10 - Invalid or Expired Game Session Key (aka PlayerHandle)
  */
  -- Added Loyalty Points
  DECLARE sessionID, serverID, gameSessionID, operatorGameID, clientStatID, gameManufacturerID BIGINT DEFAULT -1;
  DECLARE sessionGUID VARCHAR(80);
  DECLARE sessionStatusCode INT;
  DECLARE isOpen TINYINT(1) DEFAULT (0);
  
  SELECT gaming_game_sessions.game_session_id, gaming_game_sessions.client_stat_id, sessions_main.server_id, sessions_main.session_id, sessions_main.session_guid, gaming_game_sessions.is_open, operator_game_id, gaming_game_sessions.game_manufacturer_id 
  INTO gameSessionID, clientStatID, serverID, sessionID, sessionGUID, isOpen, operatorGameID, gameManufacturerID 
  FROM gaming_game_sessions
  STRAIGHT_JOIN sessions_main ON gaming_game_sessions.session_id=sessions_main.session_id 
  WHERE gaming_game_sessions.game_session_key=gameSessionKey;
  
  IF (gameSessionID = -1) THEN 
    SET statusCode = 10;
    LEAVE root;
  END IF;
	
  IF (ignoreSessionExpiry=0 AND isOpen=0) THEN 
    SET statusCode = 10;
    LEAVE root;
  END IF;
  
  CALL SessionPlayerCheckBySessionID(sessionID, serverID, componentID, ignoreSessionExpiry, extendSessionExpiry, sessionStatusCode); 
  IF (sessionStatusCode <> 0) THEN 
    SET statusCode = sessionStatusCode;
    LEAVE root;
  ELSE
      
    -- game_session
    SELECT game_session_id, game_id, operator_game_id, session_start_date, session_end_date, game_session_key, player_handle, session_id, client_stat_id, is_open, 
		total_bet, total_win, total_bet_real, total_bet_bonus, total_win_real, total_win_bonus, loyalty_points, loyalty_points_bonus, gaming_game_start_type.start_type
    FROM gaming_game_sessions
	STRAIGHT_JOIN gaming_game_start_type on gaming_game_sessions.game_start_type_id = gaming_game_start_type.game_start_type_id
    WHERE gaming_game_sessions.game_session_id=gameSessionID;
    
    -- game
    SELECT gaming_games.game_id, gaming_games.name, manufacturer_game_idf, game_name AS manufacturer_game_name, game_description, manufacturer_game_type, gaming_games.is_launchable, gaming_games.has_play_for_fun, manufacturer_game_launch_type, 
      gaming_game_manufacturers.game_manufacturer_id, gaming_game_manufacturers.name AS manufacturer_name, gaming_game_manufacturers.display_name AS manufacturer_display_name,
      gaming_operator_games.operator_game_id, gaming_operator_games.bonus_wgr_req_weigth, gaming_operator_games.promotion_wgr_req_weight,
      gaming_game_categories_games.game_category_id,gaming_license_type.license_type_id, gaming_license_type.name AS license_type,
	  gaming_games.has_auto_play,gaming_games.is_frequent_draws,gaming_games.is_passive, gaming_games.game_outcome_type_id
    FROM gaming_operator_games 
    STRAIGHT_JOIN gaming_games ON gaming_operator_games.game_id=gaming_games.game_id
    STRAIGHT_JOIN gaming_game_manufacturers ON gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id 
    STRAIGHT_JOIN gaming_game_categories_games ON gaming_games.game_id=gaming_game_categories_games.game_id
    STRAIGHT_JOIN gaming_license_type ON gaming_games.license_type_id=gaming_license_type.license_type_id
    WHERE gaming_operator_games.operator_game_id=operatorGameID;
    
    -- player_balance
    SELECT 
      IF (gaming_operator_games.disable_bonus_money=1, current_real_balance, ROUND(current_real_balance+IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0), 0)) AS current_balance, current_real_balance, 
      IF (gaming_operator_games.disable_bonus_money=1, 0, ROUND(IFNULL(Bonuses.current_bonus_balance+Bonuses.current_bonus_win_locked_balance, 0),0)) AS current_bonus_balance, gaming_currency.currency_code, ROUND(pl_exchange_rate.exchange_rate/gm_exchange_rate.exchange_rate,5) AS exchange_rate,
	  gaming_client_stats.current_ring_fenced_amount, gaming_client_stats.current_ring_fenced_sb, gaming_client_stats.current_ring_fenced_casino, gaming_client_stats.current_ring_fenced_poker, gaming_client_stats.deferred_tax
    FROM gaming_game_sessions
    STRAIGHT_JOIN gaming_client_stats ON 
		gaming_game_sessions.game_session_id=gameSessionID AND 
        gaming_game_sessions.client_stat_id=gaming_client_stats.client_stat_id
    STRAIGHT_JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
    STRAIGHT_JOIN gaming_operators ON gaming_operators.is_main_operator=1
    STRAIGHT_JOIN gaming_game_manufacturers ON gaming_game_manufacturers.game_manufacturer_id=gameManufacturerID
    LEFT JOIN gaming_operator_games ON gaming_operator_games.operator_game_id=operatorGameID
    LEFT JOIN
    (
      SELECT SUM(gbi.bonus_amount_remaining) AS current_bonus_balance, SUM(gbi.current_win_locked_amount) AS current_bonus_win_locked_balance
      FROM gaming_bonus_instances AS gbi FORCE INDEX (client_active_bonuses)
      STRAIGHT_JOIN gaming_bonus_rules_wgr_req_weights AS gbrwrw ON (gbi.client_stat_id=clientStatID AND gbi.is_active) AND
        (gbi.bonus_rule_id=gbrwrw.bonus_rule_id AND gbrwrw.operator_game_id=operatorGameID)
    ) AS Bonuses ON 1=1
    LEFT JOIN gaming_currency AS gm_currency ON gm_currency.currency_code=gaming_game_manufacturers.cw_exchange_currency
    LEFT JOIN gaming_operator_currency AS gm_exchange_rate ON gaming_operators.operator_id=gm_exchange_rate.operator_id AND gm_currency.currency_id=gm_exchange_rate.currency_id -- game_manfuacturer exchange rate
    LEFT JOIN gaming_operator_currency AS pl_exchange_rate ON gaming_operators.operator_id=pl_exchange_rate.operator_id AND pl_exchange_rate.currency_id=gaming_currency.currency_id; -- player exchange rate;
      
    SET statusCode = 0;
  END IF;
  
END root$$

DELIMITER ;

