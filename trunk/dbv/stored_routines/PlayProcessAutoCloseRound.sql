DROP procedure IF EXISTS `PlayProcessAutoCloseRound`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayProcessAutoCloseRound`()
root: BEGIN

  DECLARE autoCloseMinutes INT DEFAULT 30;
  DECLARE autoCloseRoundEnabled, noMoreRecords TINYINT(1) DEFAULT 0;
  DECLARE wagerType VARCHAR(10) DEFAULT 'Type1';
  DECLARE gameRoundID BIGINT DEFAULT -1;

  DECLARE openRoundsCursor CURSOR FOR 
	SELECT gaming_game_rounds.game_round_id
    FROM gaming_game_rounds 
	LEFT JOIN gaming_game_categories_games ON gaming_game_rounds.game_id=gaming_game_categories_games.game_id
	LEFT JOIN gaming_game_categories ON gaming_game_categories_games.game_category_id=gaming_game_categories.game_category_id
    LEFT JOIN gaming_game_categories AS parent_categ ON IFNULL(gaming_game_categories.parent_game_category_id, gaming_game_categories.game_category_id)=parent_categ.game_category_id
    WHERE gaming_game_rounds.is_round_finished=0 AND gaming_game_rounds.game_id IS NOT NULL AND gaming_game_rounds.date_time_start <
		DATE_SUB(NOW(), INTERVAL IFNULL(parent_categ.close_round_after_minutes, IFNULL(gaming_game_categories.close_round_after_minutes, autoCloseMinutes)) MINUTE)
	GROUP BY gaming_game_rounds.game_round_id LIMIT 5000;

  DECLARE CONTINUE HANDLER FOR NOT FOUND
    SET noMoreRecords = 1;

  SELECT value_bool INTO autoCloseRoundEnabled FROM gaming_settings WHERE name='AUTO_CLOSE_ROUND_ENABLED';
  SELECT value_int INTO autoCloseMinutes FROM gaming_settings WHERE name='CLOSE_AFTER_AFTER_MINUTES';  

  IF (autoCloseRoundEnabled=1) THEN
    
    OPEN openRoundsCursor;
    openRoundsLoop: LOOP 
      SET noMoreRecords=0;
      FETCH openRoundsCursor INTO gameRoundID;
      IF (noMoreRecords) THEN
        LEAVE openRoundsLoop;
      END IF;
    
	  START TRANSACTION;
	  CALL PlayCloseRound(gameRoundID, 1, 1, 0);
      COMMIT;
      
    END LOOP openRoundsLoop;
    CLOSE openRoundsCursor;
  END IF;

END root$$

DELIMITER ;

