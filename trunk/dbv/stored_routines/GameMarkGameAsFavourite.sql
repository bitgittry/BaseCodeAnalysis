DROP procedure IF EXISTS `GameMarkGameAsFavourite`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameMarkGameAsFavourite`(clientStatID BIGINT, gameID BIGINT, assingFlag INT, favouriteName VARCHAR(45), OUT statusCode INT(11))
root:BEGIN

  DECLARE rowCount,IsUnique INT(11); 
  DECLARE operatorGameID BIGINT DEFAULT -1;
  
  SET statusCode = 0;
  
  SELECT operator_game_id INTO operatorGameID FROM gaming_operator_games WHERE game_id=gameID LIMIT 1;
  
  IF (assingFlag=1) THEN 
  
	SELECT COUNT(*) INTO rowcount
	FROM gaming_client_stats_favourite_games 
    WHERE client_stat_id=clientStatID AND operator_game_id=operatorGameID;
    
    IF (operatorGameID=-1 OR rowcount > 0) THEN
		SET statusCode = 1;
		LEAVE root;
    END IF;

	SELECT COUNT(*) INTO IsUnique
	FROM gaming_client_stats_favourite_games
	WHERE client_stat_id = clientStatID AND is_player_assigned = 1 AND (favourite_name <> NULL OR favourite_name <> '') AND favourite_name = favouriteName;

	IF (IsUnique > 0) THEN
		SET statusCode = 2;
		LEAVE root;
    END IF;
    
    INSERT INTO gaming_client_stats_favourite_games (
		client_stat_id, operator_game_id, is_player_assigned, is_auto_assigned, ranking, 
		client_stats_favourite_games_counter_id, favourite_name)
    SELECT clientStatID, operatorGameID, 1, 0, 0, -1, favouriteName
    ON DUPLICATE KEY UPDATE is_player_assigned=1, favourite_name=favouriteName;
  
  ELSE  
  
    DELETE FROM gaming_client_stats_favourite_games 
    WHERE client_stat_id=clientStatID AND operator_game_id=operatorGameID;
    
  END IF;
END$$

DELIMITER ;

