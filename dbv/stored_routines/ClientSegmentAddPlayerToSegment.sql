DROP procedure IF EXISTS `ClientSegmentAddPlayerToSegment`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `ClientSegmentAddPlayerToSegment`(clientID BIGINT, newClientSegmentID BIGINT, OUT statusCode INT)
root:BEGIN
  -- Added check for payment group
  -- Adding to player selection cache even if it there is no cache entry
  
  DECLARE currentClientSegmentID, newClientSegmentIDCheck, clientSegmentGroupID, clientStatID BIGINT DEFAULT -1;
  DECLARE IsPaymentGroup, IsRiskGroup TINYINT(1);

  SELECT client_stat_id INTO clientStatID FROM gaming_client_stats WHERE client_id=clientID AND is_active;
  IF (clientStatID = -1) THEN
	SET statusCode=0;
	LEAVE root;
  END IF;

  SELECT client_segment_id, gaming_client_segments.client_segment_group_id, is_payment_group, is_risk_group
  INTO newClientSegmentIDCheck, clientSegmentGroupID, IsPaymentGroup, IsRiskGroup
  FROM gaming_client_segments
  JOIN gaming_client_segment_groups ON gaming_client_segment_groups.client_segment_group_id = gaming_client_segments.client_segment_group_id
  WHERE client_segment_id=newClientSegmentID; 
  
  IF (newClientSegmentIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;

  SELECT client_segment_id INTO currentClientSegmentID
  FROM gaming_client_segments_players
  WHERE client_segment_group_id=clientSegmentGroupID AND client_id=clientID AND is_current=1;
  
  IF (IsPaymentGroup =1) THEN
	UPDATE gaming_clients SET client_segment_id = newClientSegmentID WHERE client_id = clientID;
  END IF;

  IF (IsRiskGroup =1) THEN
	UPDATE gaming_clients SET risk_client_segment_id = newClientSegmentID WHERE client_id = clientID;
  END IF;

  IF (newClientSegmentID!=currentClientSegmentID) THEN
    SET @curDate=NOW();

    UPDATE gaming_client_segments_players SET date_to=@curDate, is_current=0 WHERE client_segment_group_id=clientSegmentGroupID AND client_id=clientID AND is_current=1;
    
    INSERT INTO gaming_client_segments_players (client_segment_group_id, client_id, client_segment_id, date_from, date_to, is_current)
    SELECT clientSegmentGroupID, clientID, newClientSegmentID, @curDate, NULL, 1
    ON DUPLICATE KEY UPDATE date_to=NULL, is_current=1,client_segment_id=newClientSegmentID;

    -- Update the Player's cache for any selections that use either the current or new segment
    INSERT INTO gaming_player_selections_player_cache(player_selection_id, client_stat_id, player_in_selection, expiry_date, last_updated)
	SELECT 	AffectedSelections.player_selection_id, 
			clientStatID, 
			(SELECT @a:=PlayerSelectionIsPlayerInSelection(AffectedSelections.player_selection_id, clientStatID)), 
			IF(@a=1, DATE_ADD(NOW(), INTERVAL (SELECT player_minutes_to_expire FROM gaming_player_selections WHERE player_selection_id = AffectedSelections.player_selection_id)  MINUTE), NULL), 
			@curDate
    FROM (
       SELECT player_selection_id FROM gaming_player_selections_client_segments WHERE client_segment_id IN (newClientSegmentID,currentClientSegmentID)
       GROUP BY player_selection_id
    ) AS AffectedSelections 
  ON DUPLICATE KEY UPDATE 
    expiry_date=IF(gaming_player_selections_player_cache.player_in_selection=0 AND VALUES(player_in_selection)=1 AND gaming_player_selections_player_cache.expiry_date IS NULL, VALUES(expiry_date), gaming_player_selections_player_cache.expiry_date),
	last_updated=IF(gaming_player_selections_player_cache.player_in_selection=VALUES(player_in_selection), gaming_player_selections_player_cache.last_updated, VALUES(last_updated)),
	player_in_selection=IF(VALUES(player_in_selection), IF(gaming_player_selections_player_cache.expiry_date<NOW(),0,1), 0);
						  


	CALL PlayerSelectionAfterUpdateCacheForPlayer(clientStatID, @curDate);
  END IF;
  

   SET statusCode=0;
END root$$

DELIMITER ;

