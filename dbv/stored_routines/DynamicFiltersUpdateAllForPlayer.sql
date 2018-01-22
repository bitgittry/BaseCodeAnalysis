DROP procedure IF EXISTS `DynamicFiltersUpdateAllForPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `DynamicFiltersUpdateAllForPlayer`(clientStatID BIGINT, forceRun TINYINT(1))
root: BEGIN
  
  -- Exluding Special Dynamic Filters
  
  DECLARE playerSelectionDynamicFilterID, playerSelectionID, clientStatIDCheck, clientID BIGINT DEFAULT -1; 
  DECLARE sessionTime DATETIME DEFAULT NULL;
  DECLARE noMoreRecords INT DEFAULT 0;
  DECLARE dateTimeForDynamicFilter DATETIME DEFAULT DATE_SUB(NOW(), INTERVAL 1 DAY);
   
  DECLARE playerFilterCursor CURSOR FOR 
    SELECT gpsdf.player_selection_id, player_selection_dynamic_filter_id 
    FROM gaming_player_selections_dynamic_filters gpsdf
	JOIN gaming_player_selections AS gps ON gpsdf.player_selection_id=gps.player_selection_id
    JOIN gaming_players_dynamic_filters AS filters ON filters.dynamic_filter_id=gpsdf.dynamic_filter_id
    LEFT JOIN gaming_bonus_rules gbr ON (gbr.player_selection_id = gpsdf.player_selection_id AND (gbr.is_active = 1 AND gbr.activation_end_date > NOW()))
    LEFT JOIN gaming_promotions gp ON (gp.player_selection_id = gpsdf.player_selection_id AND (gp.is_activated = 1 AND gp.achievement_end_date > NOW()))
    LEFT JOIN gaming_tournaments gt ON (gt.player_selection_id = gpsdf.player_selection_id AND (gt.is_active=1 AND gt.tournament_date_end > NOW()))
    LEFT JOIN gaming_rules gr ON (gr.player_selection_id = gpsdf.player_selection_id AND gr.is_active=1)
	LEFT JOIN gaming_vouchers gv ON (gv.player_selection_id = gpsdf.player_selection_id AND gv.is_active=1)
    WHERE ((gps.dynamic_filter=1 AND gps.is_frozen=0 AND filters.is_special=0) AND -- Exclude Special Dynamic Filters
		(gps.date_added>dateTimeForDynamicFilter OR gbr.bonus_rule_id IS NOT NULL OR gp.promotion_id IS NOT NULL 
			OR gt.tournament_id IS NOT NULL OR gr.rule_id IS NOT NULL OR gv.voucher_id IS NOT NULL))
    GROUP BY player_selection_dynamic_filter_id
    ORDER BY gpsdf.player_selection_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  COMMIT; 

  SELECT client_id INTO clientID FROM gaming_client_stats WHERE client_stat_id=clientStatID; 

  IF (forceRun=0) THEN
	  SELECT client_stat_id INTO clientStatIDCheck FROM gaming_client_stats 
	  WHERE client_stat_id=clientStatID AND (last_dynamic_filter_check IS NULL 
		OR IFNULL(last_dynamic_filter_check<last_played_date, 0) OR IFNULL(last_dynamic_filter_check<last_deposited_date, 0));

	  IF (clientStatIDCheck=-1) THEN
		LEAVE root;
	  END IF;
  END IF;

  OPEN playerFilterCursor;
  allPlayerFiltersLabel: LOOP 

    SET noMoreRecords = 0;
    FETCH playerFilterCursor INTO playerSelectionID, playerSelectionDynamicFilterID;

    IF (noMoreRecords) THEN
      LEAVE allPlayerFiltersLabel;
    END IF;
  
    CALL DynamicFilterUpdateForPlayer(playerSelectionDynamicFilterID, playerSelectionID, clientStatID);

  END LOOP allPlayerFiltersLabel;
  CLOSE playerFilterCursor;

  
  CALL PlayerSelectionUpdatePlayerCache(clientStatID);

  UPDATE gaming_client_stats SET last_dynamic_filter_check=NOW() WHERE client_stat_id=clientStatID;  
  
END root$$

DELIMITER ;

