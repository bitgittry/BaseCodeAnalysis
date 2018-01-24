DROP procedure IF EXISTS `PlayerSelectionDynamicFiltersUpdateAllExpired`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionDynamicFiltersUpdateAllExpired`(playerSelectionID BIGINT, overrideNextRunDate TINYINT(1))
root: BEGIN
  
  -- Excluding Special Dynamic Filters
  
  DECLARE playerSelectionDynamicFilterID BIGINT DEFAULT -1;
  DECLARE noMoreRecords, loopStatusCode INT DEFAULT 0;
   
  DECLARE playerFilterCursor CURSOR FOR 
    SELECT player_selection_dynamic_filter_id 
    FROM gaming_player_selections_dynamic_filters AS gpsdf 
	JOIN gaming_players_dynamic_filters AS filters ON filters.dynamic_filter_id=gpsdf.dynamic_filter_id AND filters.is_special=0
    WHERE gpsdf.player_selection_id=playerSelectionID AND (gpsdf.next_run_date <= NOW() OR gpsdf.next_run_date IS NULL OR overrideNextRunDate);
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
    
  SET @playerSelectionID = playerSelectionID;
  
  OPEN playerFilterCursor;
  allPlayerFiltersLabel: LOOP 
    
	SET noMoreRecords = 0;
    FETCH playerFilterCursor INTO playerSelectionDynamicFilterID;
    IF (noMoreRecords) THEN
      LEAVE allPlayerFiltersLabel;
    END IF;
  
    SET loopStatusCode=0;
    CALL DynamicFilterUpdate(playerSelectionDynamicFilterID, playerSelectionID, loopStatusCode);
  
  END LOOP allPlayerFiltersLabel;
  CLOSE playerFilterCursor;
  
END root$$

DELIMITER ;

