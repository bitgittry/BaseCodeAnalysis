DROP procedure IF EXISTS `ClientSegmentRemovePlayerFromSegment`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ClientSegmentRemovePlayerFromSegment`(clientID BIGINT, oldClientSegmentID BIGINT, addToDefaultSegment TINYINT(1), OUT statusCode INT)
root:BEGIN
  -- Added call to PlayerSelectionAfterUpdateCacheForPlayer
  
  DECLARE currentClientSegmentID, oldClientSegmentIDCheck, clientSegmentGroupID, defaultClientSegmentID, clientStatID BIGINT DEFAULT -1;
  
  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_id=clientID AND is_active;
  IF (clientStatID = -1) THEN
	SET statusCode=0;
	LEAVE root;
  END IF;

  SELECT client_segment_id, client_segment_group_id 
  INTO oldClientSegmentIDCheck, clientSegmentGroupID
  FROM gaming_client_segments WHERE client_segment_id=oldClientSegmentID; 
  
  IF (oldClientSegmentIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  IF (clientSegmentGroupID!=-1) THEN
    SET @curDate=NOW();
    
    UPDATE gaming_client_segments_players SET date_to=@curDate, is_current=0 WHERE client_segment_group_id=clientSegmentGroupID AND client_id=clientID AND is_current=1;
    
    IF (addToDefaultSegment) THEN 
      SELECT client_segment_id INTO defaultClientSegmentID FROM gaming_client_segments WHERE client_segment_group_id=clientSegmentGroupID AND is_default=1 LIMIT 1;
      
	  INSERT INTO gaming_client_segments_players (client_segment_group_id, client_id, client_segment_id, date_from, date_to, is_current)
      SELECT clientSegmentGroupID, clientID, defaultClientSegmentID, @curDate, NULL, 1
      ON DUPLICATE KEY UPDATE client_segment_id=defaultClientSegmentID;
    END IF;

	-- Update the Player's cache for any selections that use either the current or new segment
    UPDATE gaming_player_selections_player_cache AS PlayerCache 
    JOIN (
       SELECT player_selection_id FROM gaming_player_selections_client_segments WHERE client_segment_id IN (oldClientSegmentID,defaultClientSegmentID)
       GROUP BY player_selection_id
    ) AS AffectedSelections ON PlayerCache.client_stat_id=clientStatID AND PlayerCache.player_selection_id=AffectedSelections.player_selection_id
    SET PlayerCache.player_in_selection= ((@a := PlayerCache.player_in_selection) OR 1=1) AND PlayerSelectionIsPlayerInSelection(AffectedSelections.player_selection_id, clientStatID),
		PlayerCache.last_updated = IF(@a!=PlayerCache.player_in_selection, @curDate, PlayerCache.last_updated),
		PlayerCache.expiry_date = IF(@a=0 AND PlayerCache.player_in_selection = 1 AND PlayerCache.expiry_date IS NULL, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = PlayerCache.player_selection_id)  MINUTE), PlayerCache.expiry_date);
        
	CALL PlayerSelectionAfterUpdateCacheForPlayer(clientStatID, @curDate);
  
  END IF;
  
  SET statusCode=0;
  
END root$$

DELIMITER ;

