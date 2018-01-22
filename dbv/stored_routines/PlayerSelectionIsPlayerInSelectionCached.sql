DROP function IF EXISTS `PlayerSelectionIsPlayerInSelectionCached`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayerSelectionIsPlayerInSelectionCached`(playerSelectionID BIGINT, clientStatID BIGINT) RETURNS tinyint(1)
    READS SQL DATA
BEGIN
  -- Now saving in cache
  -- Added on duplicate key update
  -- now calling directly PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter  
  DECLARE inSelection 	TINYINT(1) DEFAULT NULL;
  DECLARE expiryDate 	DATETIME DEFAULT NULL;

  SELECT player_in_selection,expiry_date INTO inSelection, expiryDate
  FROM gaming_player_selections_player_cache AS cache 
  WHERE player_selection_id=playerSelectionID AND client_stat_id=clientStatID;
  
  IF (inSelection IS NULL) THEN
	-- player is not in cache
	SET inSelection=IFNULL(PlayerSelectionIsPlayerInSelectionWithExcludeDynamicFilter(playerSelectionID, clientStatID, 0, 1),0);
    SET @updatedDate=NOW();

	SET expiryDate = DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = playerSelectionID)  MINUTE);

	INSERT INTO gaming_player_selections_player_cache (player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
    VALUES (playerSelectionID, clientStatID, inSelection, IF(inSelection=1, expiryDate, NULL) , @updatedDate)
    ON DUPLICATE KEY UPDATE 
							expiry_date=IF(player_in_selection=0 AND VALUES(player_in_selection)=1, expiryDate, expiry_date),
							player_in_selection=VALUES(player_in_selection), 
						    last_updated=@updatedDate;
	
	CALL PlayerSelectionAfterUpdateCacheForPlayer(clientStatID, @updatedDate);

  END IF;

  RETURN inSelection AND ((expiryDate IS NOT NULL AND expiryDate > NOW()) OR expiryDate IS NULL);
END$$

DELIMITER ;
