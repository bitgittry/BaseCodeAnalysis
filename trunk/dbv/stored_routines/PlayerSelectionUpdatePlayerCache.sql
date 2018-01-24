DROP procedure IF EXISTS `PlayerSelectionUpdatePlayerCache`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionUpdatePlayerCache`(clientStatID BIGINT)
BEGIN
  
  -- Added for player selections created less than 24 hours ago
  -- Added Player Selection with ID: 1
  
  DECLARE curDateTemp DATETIME DEFAULT NOW(); 
  DECLARE bonusOnly TINYINT(1) DEFAULT 0;
  DECLARE dateTimeForDynamicFilter DATETIME DEFAULT DATE_SUB(NOW(), INTERVAL 1 DAY);
  DECLARE clientID, sessionID BIGINT DEFAULT -1;

  COMMIT; 

  SELECT value_bool INTO bonusOnly FROM gaming_settings WHERE `name`='PLAYER_SELECTION_PLAYER_UPDATE_CACHE_BONUS_ONLY';
  
  
  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
  SELECT gaming_player_selections.player_selection_id, clientStatID, 
		(SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_player_selections.player_selection_id,clientStatID) AS cache_new_value), 
		IF(@a=1, DATE_ADD(NOW(), INTERVAL gaming_player_selections.player_minutes_to_expire MINUTE), NULL),
		curDateTemp
  FROM gaming_player_selections
  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_player_selections.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  WHERE (gaming_player_selections.date_added>dateTimeForDynamicFilter AND gaming_player_selections.is_hidden=0) OR gaming_player_selections.player_selection_id=1
		  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
								  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
								  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);
  
  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
  SELECT gaming_bonus_rules.player_selection_id, clientStatID, 
		(SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_bonus_rules.player_selection_id,clientStatID) AS cache_new_value), 
		IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE gaming_player_selections.player_selection_id = gaming_bonus_rules.player_selection_id)  MINUTE), NULL),
		curDateTemp
  FROM gaming_bonus_rules
  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  WHERE activation_end_date >= curDateTemp AND gaming_bonus_rules.is_active=1
		  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
								  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
								  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);

  IF (bonusOnly=0) THEN

	  
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	  SELECT gaming_promotions.player_selection_id, 
			clientStatID, 
			(SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_promotions.player_selection_id,clientStatID) AS cache_new_value) AS cache_new_value, 
			IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_promotions.player_selection_id)  MINUTE), NULL),
			curDateTemp
	  FROM gaming_promotions
	  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_promotions.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	  WHERE achievement_end_date > curDateTemp AND gaming_promotions.is_active=1 AND gaming_promotions.is_child=0 
	  GROUP BY gaming_promotions.player_selection_id
	  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
							  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
							  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);
	  
	  
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	  SELECT gaming_tournaments.player_selection_id, 
			 clientStatID, 
			 (SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_tournaments.player_selection_id,clientStatID)) AS cache_new_value, 
			 IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_tournaments.player_selection_id)  MINUTE), cache.expiry_date),
			 curDateTemp
	  FROM gaming_tournaments
	  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_tournaments.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	  WHERE gaming_tournaments.tournament_date_end > curDateTemp AND gaming_tournaments.is_active=1 
	  GROUP BY gaming_tournaments.player_selection_id
	  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
							  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
							  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);

	  
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	  SELECT gaming_rules.player_selection_id, clientStatID, 
			  (SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_rules.player_selection_id,clientStatID)) AS cache_new_value, 
			  IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_rules.player_selection_id)  MINUTE), cache.expiry_date),
			  curDateTemp
	  FROM gaming_rules
	  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	  WHERE gaming_rules.is_active=1 
	  GROUP BY gaming_rules.player_selection_id	
	  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
							  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
							  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);

	  
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	  SELECT gaming_loyalty_redemption.player_selection_id, clientStatID, 
			 (SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_loyalty_redemption.player_selection_id,clientStatID)) AS cache_new_value, 
			 IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_loyalty_redemption.player_selection_id)  MINUTE), cache.expiry_date),
			curDateTemp
	  FROM gaming_loyalty_redemption
	  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_loyalty_redemption.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	  WHERE gaming_loyalty_redemption.is_active=1 AND gaming_loyalty_redemption.player_selection_id IS NOT NULL 
	  GROUP BY gaming_loyalty_redemption.player_selection_id	
	  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
							  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
							  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);

	  
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	  SELECT gaming_player_selections.player_selection_id, clientStatID, 
			(SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_player_selections.player_selection_id,clientStatID)) AS cache_new_value, 
			 IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = cache.player_selection_id)  MINUTE), cache.expiry_date),
			curDateTemp
	  FROM gaming_player_selections
	  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_player_selections.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	  WHERE gaming_player_selections.force_run_dynamic_filter=1 AND gaming_player_selections.dynamic_filter=1 AND (gaming_player_selections.is_hidden=0 OR gaming_player_selections.date_added>dateTimeForDynamicFilter)
	  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
							  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
							  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);

	  
	  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	  SELECT gaming_vouchers.player_selection_id, clientStatID, 
			(SELECT @a:= PlayerSelectionIsPlayerInSelection(gaming_vouchers.player_selection_id,clientStatID)) AS cache_new_value, 
			IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_vouchers.player_selection_id)  MINUTE), cache.expiry_date),
			curDateTemp
	  FROM gaming_vouchers
	  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_vouchers.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
	  WHERE deactivation_date >= curDateTemp AND gaming_vouchers.is_active=1 
	  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
							  gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), 
							  gaming_player_selections_player_cache.last_updated=VALUES(last_updated);

  END IF;

  CALL PlayerSelectionAfterUpdateCacheForPlayer(clientStatID, curDateTemp);
 
  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  SELECT session_id INTO sessionID FROM sessions_main FORCE INDEX (client_active_session) WHERE extra_id=clientID AND status_code=1 LIMIT 1;
  
  IF (sessionID != -1) THEN
    START TRANSACTION;
	CALL BonusCheckAwardingOnLogin(sessionID, clientStatID, NULL);
    COMMIT;
  END IF;

END$$

DELIMITER ;

