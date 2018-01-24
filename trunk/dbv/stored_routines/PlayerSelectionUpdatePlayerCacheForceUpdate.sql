DROP procedure IF EXISTS `PlayerSelectionUpdatePlayerCacheForceUpdate`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionUpdatePlayerCacheForceUpdate`(clientStatID BIGINT)
BEGIN

  SET @curDateTemp = NOW();

  UPDATE gaming_promotions
  JOIN gaming_player_selections_player_cache AS cache ON gaming_promotions.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  SET cache.player_in_selection=((@a := cache.player_in_selection) OR 1=1) -- Store the old value of player_in_selection in @a and respect the result of PlayerSelectionIsPlayerInSelection
		AND PlayerSelectionIsPlayerInSelection(gaming_promotions.player_selection_id,clientStatID),
		cache.expiry_date = IF(@a=0 AND cache.player_in_selection = 1 AND cache.expiry_date IS NULL, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = cache.player_in_selection)  MINUTE), cache.expiry_date),
		last_updated=NOW()
  WHERE achievement_end_date >= @curDateTemp AND gaming_promotions.is_active=1 AND gaming_promotions.is_child=0; 
  
  UPDATE gaming_bonus_rules
  JOIN gaming_player_selections_player_cache AS cache ON gaming_bonus_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  SET cache.player_in_selection=((@a := cache.player_in_selection) OR 1=1) -- Store the old value of player_in_selection in @a and respect the result of PlayerSelectionIsPlayerInSelection
		AND PlayerSelectionIsPlayerInSelection(gaming_bonus_rules.player_selection_id,clientStatID), 
		cache.expiry_date = IF(@a=0 AND cache.player_in_selection = 1 AND cache.expiry_date IS NULL, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = cache.player_in_selection)  MINUTE), cache.expiry_date),
		last_updated=NOW()
  WHERE activation_end_date >= @curDateTemp AND gaming_bonus_rules.is_active=1;  
   
  UPDATE gaming_rules
  JOIN gaming_player_selections_player_cache AS cache ON gaming_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  SET cache.player_in_selection=((@a := cache.player_in_selection) OR 1=1) -- Store the old value of player_in_selection in @a and respect the result of PlayerSelectionIsPlayerInSelection
	AND PlayerSelectionIsPlayerInSelection(gaming_rules.player_selection_id,clientStatID), 
	cache.expiry_date = IF(@a=0 AND cache.player_in_selection = 1 AND cache.expiry_date IS NULL, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = cache.player_in_selection)  MINUTE), cache.expiry_date),
	last_updated=NOW()
  WHERE gaming_rules.is_active=1;  


END$$

DELIMITER ;

