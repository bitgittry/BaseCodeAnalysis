DROP procedure IF EXISTS `PlayerSelectionUpdatePlayerCacheVouchers`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionUpdatePlayerCacheVouchers`(clientStatID BIGINT)
BEGIN
  -- Optimized
  -- Added PlayerSelectionAfterUpdateCacheForPlayer
  DECLARE curDateTemp DATETIME DEFAULT NOW();

  COMMIT;  

  INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
  SELECT gaming_vouchers.player_selection_id, 
		 clientStatID, 
		 (SELECT @a:= IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_vouchers.player_selection_id,clientStatID))) AS cache_new_value, 
		 IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = gaming_vouchers.player_selection_id)  MINUTE), cache.expiry_date),
		 curDateTemp
  FROM gaming_vouchers
  LEFT JOIN gaming_player_selections_player_cache AS cache ON gaming_vouchers.player_selection_id=cache.player_selection_id AND cache.client_stat_id=clientStatID
  WHERE deactivation_date >= curDateTemp AND gaming_vouchers.is_active=1 AND cache.player_in_selection IS NULL 
  ON DUPLICATE KEY UPDATE gaming_player_selections_player_cache.expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
						  gaming_player_selections_player_cache.player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0),
						  gaming_player_selections_player_cache.last_updated=curDateTemp;

  IF (ROW_COUNT()>0) THEN
    CALL PlayerSelectionAfterUpdateCacheForPlayer(clientStatID, curDateTemp);
  END IF;
END$$

DELIMITER ;

