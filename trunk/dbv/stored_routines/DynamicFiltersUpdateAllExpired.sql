DROP procedure IF EXISTS `DynamicFiltersUpdateAllExpired`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `DynamicFiltersUpdateAllExpired`()
root: BEGIN
  -- Added a join for player selections used for greeting messages
  
  DECLARE playerSelectionDynamicFilterID, playerSelectionID, curPlayerSelection BIGINT DEFAULT -1;
  DECLARE noMoreRecords, loopStatusCode INT DEFAULT 0;
    
  DECLARE playerFilterCursor CURSOR FOR 
    SELECT gps.player_selection_id 
    FROM gaming_player_selections AS gps
    JOIN gaming_player_selections_dynamic_filters AS gpsdf ON gpsdf.player_selection_id = gps.player_selection_id
    LEFT JOIN gaming_bonus_rules gbr ON (gbr.player_selection_id = gpsdf.player_selection_id AND (gbr.is_active = 1 AND gbr.activation_end_date > NOW()))
    LEFT JOIN gaming_promotions gp ON (gp.player_selection_id = gpsdf.player_selection_id AND (gp.is_activated = 1 AND gp.achievement_end_date > NOW()))
    LEFT JOIN gaming_tournaments gt ON (gt.player_selection_id = gpsdf.player_selection_id AND (gt.is_active=1 AND gt.tournament_date_end > NOW()))
    LEFT JOIN gaming_message_greetings gmg ON (gmg.player_selection_id = gpsdf.player_selection_id AND gmg.is_hidden=0 AND ((gmg.is_never_ending=0 AND gmg.date_to > NOW()) OR (gmg.is_never_ending=1 AND gmg.date_to IS NULL)))
    LEFT JOIN gaming_communication_messages gcm ON (gcm.player_selection_id = gpsdf.player_selection_id AND gcm.is_active=1 AND ((gcm.is_never_ending=0 AND gcm.end_date > NOW()) OR (gcm.is_never_ending=1 )))
    WHERE (gpsdf.next_run_date <= NOW() OR gpsdf.next_run_date IS NULL) AND gps.is_frozen=0 AND
      (gbr.bonus_rule_id IS NOT NULL OR gp.promotion_id IS NOT NULL OR gt.tournament_id IS NOT NULL OR gpsdf.force_run = 1 OR gmg.message_greeting_id IS NOT NULL OR gcm.communication_message_id IS NOT NULL)
    GROUP BY gps.player_selection_id;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;
  
  COMMIT; 

  OPEN playerFilterCursor;
  allPlayerFiltersLabel: LOOP 

    SET noMoreRecords = 0;
    FETCH playerFilterCursor INTO playerSelectionID;
    
	IF (noMoreRecords) THEN
      LEAVE allPlayerFiltersLabel;
    END IF;  

    -- the following SP iterates internally through all filters of the selection and calls DynamicFilterUpdate for each of them
    CALL PlayerSelectionUpdatePSelectionCache(playerSelectionID, 1, 1, 1);	

  END LOOP allPlayerFiltersLabel;
  CLOSE playerFilterCursor;

END root$$

DELIMITER ;

