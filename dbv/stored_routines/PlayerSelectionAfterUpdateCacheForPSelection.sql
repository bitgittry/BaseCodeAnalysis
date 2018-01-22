DROP procedure IF EXISTS `PlayerSelectionAfterUpdateCacheForPSelection`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionAfterUpdateCacheForPSelection`(playerSelectionID BIGINT, isTopLevel TINYINT(1), updatedDate DATETIME)
BEGIN
  -- First Version

  DECLARE historyEnabled TINYINT(1) DEFAULT 0;
  DECLARE systemEndDate DATETIME DEFAULT '3000-01-01';
  DECLARE updateDateMinusSecond DATETIME DEFAULT DATE_SUB(updatedDate, INTERVAL 1 SECOND);
  
  SELECT value_bool INTO historyEnabled FROM gaming_settings WHERE `name`='PLAYER_SELECTION_SAVE_CACHE_HISTORY';

  -- cache history for the whole player selection
  IF (historyEnabled) THEN

	  SET @updateDateMinusSecond=DATE_SUB(@updatedDate, INTERVAL 1 SECOND);

	  UPDATE gaming_player_selections_player_cache_history AS cache_history
	  JOIN gaming_player_selections_player_cache AS cache ON
		(cache.player_selection_id=playerSelectionID AND cache.last_updated=@updatedDate) AND
		(cache.player_selection_id=cache_history.player_selection_id AND cache.client_Stat_id=cache_history.client_stat_id AND cache_history.is_current) AND
		cache.player_in_selection!=cache_history.player_in_selection
	  SET is_current=0, date_to=@updateDateMinusSecond;

	  INSERT INTO gaming_player_selections_player_cache_history (player_selection_id, client_stat_id, is_current, date_from, date_to, player_in_selection)
	  SELECT playerSelectionID, cache.client_stat_id, 1, @updatedDate, systemEndDate, cache.player_in_selection
	  FROM gaming_player_selections_player_cache AS cache 
	  LEFT JOIN gaming_player_selections_player_cache_history AS cache_history ON 		
		(cache.player_selection_id=cache_history.player_selection_id AND cache.client_Stat_id=cache_history.client_stat_id AND cache_history.is_current)
	  WHERE (cache.player_selection_id=playerSelectionID AND cache.last_updated=@updatedDate) AND
		(cache_history.player_selection_id IS NULL OR cache.player_in_selection!=cache_history.player_in_selection);

  END IF;

  -- Update parent selections cache 
  IF (isTopLevel=1) THEN
	CALL PlayerSelectionUpdateParentSelectionCache(playerSelectionID);
  END IF;

END$$

DELIMITER ;

