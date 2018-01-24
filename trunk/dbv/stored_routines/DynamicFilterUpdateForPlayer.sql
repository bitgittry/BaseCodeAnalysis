DROP procedure IF EXISTS `DynamicFilterUpdateForPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `DynamicFilterUpdateForPlayer`(playerSelectionDynamicFilterID BIGINT, playerSelectionID BIGINT, clientStatID BIGINT)
root: BEGIN
  -- SET @clientStatID=clientStatID before calling DynamicFilterGetQueryString to get query optimized for particular player
  -- Optimized
  -- Invalidating cache of player selection if dynamic filter status for the player changed 
  -- Caching dynamic filter
   
  DECLARE changeDateStatusCode, numUpdated, numDeleted INT DEFAULT 0;

  IF (playerSelectionDynamicFilterID=-1) THEN 
    LEAVE root;
  END IF;
  
  
  SET @clientStatID = clientStatID;
  SET @query_string = (SELECT DynamicFilterGetQueryString(playerSelectionDynamicFilterID));
  
  IF (@query_string IS NULL) THEN
    LEAVE root;
  END IF;

  SET @playerSelectionID = playerSelectionID;

	 SELECT
	   gaming_player_selections.player_selection_id, open_to_all, selected_players, group_selection, player_selection, client_segment, 
	   player_filter, dynamic_filter_on_selection, gaming_player_filters.player_filter_id, exclude_bonus_seeker, exclude_bonus_dont_want, client_segments_num_match, dynamic_filters_num_match
	 INTO @playerSelectionID, @openToAllFlag, @selectedPlayersFlag, @groupSelectionFlag, @playerSelectionFlag, @clientSegmentFlag, 
		@playerFilterFlag, @dynamic_filter_on_selection, @playerFilterID, @excludeBonusSeeker, @excludeBonusDontWant, @clientSegmentsNumMatch, @dynamicFiltersNumMatch
	 FROM gaming_player_selections FORCE INDEX (PRIMARY)
	 LEFT JOIN gaming_player_filters ON 
	   gaming_player_selections.player_selection_id=playerSelectionID AND 
	   gaming_player_selections.player_selection_id=gaming_player_filters.player_selection_id      
	 WHERE gaming_player_selections.player_selection_id=playerSelectionID;

  SET @playerSelectionDynamicFilterID=playerSelectionDynamicFilterID;
  
  SET @lastUpdatedDate=NOW();
  
  PREPARE stmt1 FROM @query_string;
  EXECUTE stmt1; 
  SET numUpdated=ROW_COUNT();
  DEALLOCATE PREPARE  stmt1;
  
  DELETE gaming_player_selections_dynamic_filter_players FROM gaming_player_selections_dynamic_filter_players FORCE INDEX (PRIMARY)
  WHERE player_selection_dynamic_filter_id=playerSelectionDynamicFilterID AND client_stat_id=clientStatID AND last_updated_date!=@lastUpdatedDate;
  SET numDeleted=ROW_COUNT();

  IF (numUpdated=1 OR numDeleted=1) THEN -- if entry was only updated then we would have numUpdated=2
	  UPDATE gaming_player_selections_player_cache AS gpspc FORCE INDEX (PRIMARY)  
	  SET gpspc.player_in_selection=NULL 
	  WHERE gpspc.player_selection_id=playerSelectionID AND gpspc.client_stat_id=clientStatID;
  END IF;

END root$$

DELIMITER ;

