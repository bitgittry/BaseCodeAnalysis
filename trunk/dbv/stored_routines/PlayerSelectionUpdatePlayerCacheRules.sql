DROP procedure IF EXISTS `PlayerSelectionUpdatePlayerCacheRules`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionUpdatePlayerCacheRules`(clientStatID BIGINT)
BEGIN
  -- Optimized
  -- Added PlayerSelectionAfterUpdateCacheForPlayer
  DECLARE curDateTemp DATETIME DEFAULT NOW();

  COMMIT;
	
  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, last_updated)
  SELECT gaming_rules.player_selection_id, clientStatID, IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_rules.player_selection_id,clientStatID)) AS cache_new_value, curDateTemp
  FROM gaming_rules
  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_rules.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  WHERE gaming_rules.is_active=1 AND cache.player_in_selection IS NULL 
  ON DUPLICATE KEY UPDATE player_in_selection=VALUES(player_in_selection), last_updated=curDateTemp;
  
  IF (ROW_COUNT()>0) THEN
    CALL PlayerSelectionAfterUpdateCacheForPlayer(clientStatID, curDateTemp);
  END IF;
END$$

DELIMITER ;

