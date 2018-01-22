DROP procedure IF EXISTS `PlayerSelectionUpdateParentSelectionCache`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayerSelectionUpdateParentSelectionCache`(playerSelectionID BIGINT)
BEGIN
  -- Loops through all the parent selections and updates their cache
  DECLARE noMoreRecords, updateParentCache TINYINT(1) DEFAULT 0;
  DECLARE parentPlayerSelectionID BIGINT DEFAULT -1;

  DECLARE parentSelectionsCursor CURSOR FOR 
    SELECT gaming_player_selections.player_selection_id 
    FROM gaming_player_selections_child_selections AS child_selections 
    JOIN gaming_player_selections ON child_selections.player_selection_id=gaming_player_selections.player_selection_id AND gaming_player_selections.is_frozen=0
    WHERE child_selections.child_player_selection_id=playerSelectionID;
  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SELECT value_bool INTO updateParentCache FROM gaming_settings WHERE `name`='PLAYER_SELECTION_UPDATE_PARENT_CACHE';  

  IF (updateParentCache) THEN

	  OPEN parentSelectionsCursor;
	  parentSelectionsLabel: LOOP 
		SET noMoreRecords=0;
		FETCH parentSelectionsCursor INTO parentPlayerSelectionID;
		IF (noMoreRecords) THEN
		  LEAVE parentSelectionsLabel;
		END IF;
	  
		CALL PlayerSelectionUpdatePSelectionCache(parentPlayerSelectionID, 1, 0, 0);

	  END LOOP parentSelectionsLabel;
	  CLOSE parentSelectionsCursor;
	
  END IF;

END$$

DELIMITER ;

