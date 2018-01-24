DROP procedure IF EXISTS `DynamicFilterUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `DynamicFilterUpdate`(playerSelectionDynamicFilterID BIGINT, playerSelectionID BIGINT,OUT statusCode INT)
root: BEGIN
  
  -- Optimized: inserts on duplicate key update and then deletes. Before it was deleting all entries and inserting again which could have misssed some players which checked the cache in the interem.
  -- SET @clientStatID=0 before calling DynamicFilterGetQueryString to get query optimized for all players 
  DECLARE changeDateStatusCode INT DEFAULT 0;

  IF (playerSelectionDynamicFilterID=-1) THEN 
    SET statusCode=1;
    LEAVE root;
  END IF;
   
  SET @clientStatID=0;  
  SET @query_string = (SELECT DynamicFilterGetQueryString(playerSelectionDynamicFilterID));
  
  IF (@query_string IS NULL) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;

  SET @playerSelectionID = playerSelectionID;
  SET @updatedDate=NOW();

	 SELECT 
	   gaming_player_selections.player_selection_id, open_to_all, selected_players, group_selection, player_selection, client_segment, player_filter, 
		dynamic_filter_on_selection, gaming_player_filters.player_filter_id, exclude_bonus_seeker, exclude_bonus_dont_want, client_segments_num_match, dynamic_filters_num_match
	 INTO @playerSelectionID, @openToAllFlag, @selectedPlayersFlag, @groupSelectionFlag, @playerSelectionFlag, @clientSegmentFlag, @playerFilterFlag, 
		@dynamic_filter_on_selection, @playerFilterID, @excludeBonusSeeker, @excludeBonusDontWant, @clientSegmentsNumMatch, @dynamicFiltersNumMatch
	 FROM gaming_player_selections 
	 LEFT JOIN gaming_player_filters ON 
	   gaming_player_selections.player_selection_id=playerSelectionID AND 
	   gaming_player_selections.player_selection_id=gaming_player_filters.player_selection_id      
	 WHERE gaming_player_selections.player_selection_id=playerSelectionID;

  SET @s = CONCAT('INSERT INTO gaming_player_selections_dynamic_filter_players (player_selection_dynamic_filter_id, client_stat_id, last_updated_date) 
	SELECT ?, temp_table.client_stat_id, @updatedDate FROM ( ',@query_string,' ) AS temp_table 
    STRAIGHT_JOIN gaming_client_stats ON gaming_client_stats.client_stat_id=temp_table.client_stat_id
    STRAIGHT_JOIN gaming_clients ON gaming_client_stats.client_id=gaming_clients.client_id AND gaming_clients.is_account_closed=0
    ON DUPLICATE KEY UPDATE last_updated_date=@updatedDate;');


  PREPARE stmt1 FROM @s;
  SET @playerSelectionDynamicFilterID=playerSelectionDynamicFilterID;
  EXECUTE stmt1 USING @playerSelectionDynamicFilterID;
  DEALLOCATE PREPARE  stmt1;

  DELETE FROM gaming_player_selections_dynamic_filter_players WHERE player_selection_dynamic_filter_id=@playerSelectionDynamicFilterID AND last_updated_date<@updatedDate; 

  UPDATE gaming_player_selections_dynamic_filters SET last_run_date=NOW(), force_run=0 WHERE player_selection_dynamic_filter_id=playerSelectionDynamicFilterID;  
  
  -- CALL DynamicFilterPlayerSelectionUpdateRunOnEnd(playerSelectionDynamicFilterID, changeDateStatusCode);
  -- below optimized the workflow from the above SP  
  
  UPDATE gaming_player_selections_dynamic_filters AS gpsdf
  JOIN gaming_players_dynamic_filters AS gpdf ON gpdf.dynamic_filter_id = gpsdf.dynamic_filter_id
  JOIN gaming_query_date_intervals AS gqdi FORCE INDEX (interval_type_date_from_date_to) ON gqdi.query_date_interval_type_id = gpdf.query_date_interval_type_id
  SET
    gpsdf.current_query_date_interval_id = gqdi.query_date_interval_id,
    gpsdf.next_run_date = DATE_ADD(gqdi.date_to, INTERVAL (gpdf.offset_minutes_from_interval * 60 + 1) SECOND)
  WHERE gpsdf.player_selection_dynamic_filter_id = playerSelectionDynamicFilterID AND gpdf.use_date_intervals = 1 AND NOW() BETWEEN gqdi.date_from AND gqdi.date_to;
    
  SET statusCode=0;
END root$$

DELIMITER ;

