DROP procedure IF EXISTS `PlayerSelectionAfterUpdateCacheForPlayer`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionAfterUpdateCacheForPlayer`(clientStatID BIGINT, updatedDate DATETIME)
root: BEGIN
  -- added update of parent selection
  -- added cache history 
  DECLARE historyEnabled, updateParentCache TINYINT(1) DEFAULT 0;
  DECLARE systemEndDate DATETIME DEFAULT '3000-01-01';
  DECLARE updateDateMinusSecond DATETIME DEFAULT DATE_SUB(updatedDate, INTERVAL 1 SECOND);

  SELECT value_bool INTO updateParentCache FROM gaming_settings WHERE `name`='PLAYER_SELECTION_UPDATE_PARENT_CACHE'; 
 

   -- parent selections update cache
  IF (updateParentCache) THEN

   -- player_in_selection: 
	  -- 1) if cache PlayerSelectionIsPlayerInSelection is true, set cache.player_in_selection as true. 
	  -- 2) if cache->child PlayerSelectionIsPlayerInSelection is true, set cache.player_in_selection as true. 
	  -- 3) otherwise it is not in player selection, and not in children/bundle player selections.
	  
	  -- expiry_date: 1) if it was not in selection, and now it is & expiryDate not set, add a default value for expiryDate. 
	  -- 		 	  2) otherwise keep same value
  

	UPDATE 		gaming_player_selections_player_cache AS cache
				LEFT JOIN gaming_player_selections_child_selections AS child_selections 
				ON child_selections.child_player_selection_id = cache.player_selection_id					
	SET cache.player_in_selection = (
													((@a := cache.player_in_selection)) 
													AND													
													IF( PlayerSelectionIsPlayerInSelection(cache.player_selection_id,cache.client_stat_id) OR 
												(IF((IFNULL(child_selections.player_selection_id, -1) = -1), 0 , PlayerSelectionIsPlayerInSelection(child_selections.player_selection_id, cache.client_stat_id)) = 1), 1, 0)
								     ),
	cache.last_updated = updatedDate, 
	cache.expiry_date =  IF( (@a = 0) AND (cache.player_in_selection = 1) AND (cache.expiry_date IS NULL),	
							(DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = cache.player_selection_id) MINUTE)),
							cache.expiry_date )  						
	WHERE cache.client_stat_id = clientStatID AND cache.last_updated = updatedDate;
	  
  END IF;


  SELECT value_bool INTO historyEnabled FROM gaming_settings WHERE `name`='PLAYER_SELECTION_SAVE_CACHE_HISTORY';
  
  -- history
  IF (historyEnabled) THEN

	  SELECT value_date INTO systemEndDate FROM gaming_settings WHERE `name`='SYSTEM_END_DATE';

	  UPDATE gaming_player_selections_player_cache_history AS cache_history
	  JOIN gaming_player_selections_player_cache AS cache ON
		(cache.client_stat_id=clientStatID AND cache.last_updated=updatedDate) AND
		(cache.player_selection_id=cache_history.player_selection_id AND cache.client_Stat_id=cache_history.client_stat_id AND cache_history.is_current) AND
		cache.player_in_selection!=cache_history.player_in_selection
	  SET is_current=0, date_to=updateDateMinusSecond;

	  INSERT INTO gaming_player_selections_player_cache_history (player_selection_id, client_stat_id, is_current, date_from, date_to, player_in_selection)
	  SELECT cache.player_selection_id, cache.client_stat_id, 1, updatedDate, systemEndDate, cache.player_in_selection
	  FROM gaming_player_selections_player_cache AS cache 
	  LEFT JOIN gaming_player_selections_player_cache_history AS cache_history ON 
		(cache.player_selection_id=cache_history.player_selection_id AND cache.client_Stat_id=cache_history.client_stat_id AND cache_history.is_current)
	  WHERE (cache.client_stat_id=clientStatID AND cache.last_updated=updatedDate) AND
		(cache_history.player_selection_id IS NULL OR cache_history.player_in_selection!=cache.player_in_selection);
  END IF;


END root$$

DELIMITER ;

