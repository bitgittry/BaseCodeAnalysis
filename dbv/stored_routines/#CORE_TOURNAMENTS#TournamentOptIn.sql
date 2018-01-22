
DROP procedure IF EXISTS `TournamentOptIn`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentOptIn`(tournamentID BIGINT, clientStatID BIGINT, evenIfNotInSelection TINYINT(1), OUT statusCode INT, OUT tournamentStatusID BIGINT)
root:BEGIN
  
  DECLARE checkValue, tournamentIDCheck, playerSelectionID BIGINT DEFAULT 0;
  DECLARE doesExist BIGINT DEFAULT NULL;
  DECLARE tournamentDateEnd DATETIME;
  
  SELECT client_stat_id FROM gaming_client_stats WHERE client_stat_id=clientStatID FOR UPDATE;
  
  SELECT client_stat_id INTO checkValue FROM gaming_client_stats WHERE client_stat_id=clientStatID;
  IF (checkValue=0) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
  
  SELECT tournament_id, player_selection_id, tournament_date_end INTO tournamentIDCheck, playerSelectionID, tournamentDateEnd
  FROM gaming_tournaments WHERE tournament_id=tournamentID AND is_active=1;
  
  IF (tournamentIDCheck=0) THEN
    SET statusCode=2 ;
    LEAVE root;
  END IF;
  
  IF (tournamentDateEnd<NOW()) THEN
    SET statusCode=3;
    LEAVE root;
  END IF;
  
  IF (evenIfNotInSelection = 0) THEN 
    IF (PlayerSelectionIsPlayerInSelection(playerSelectionID, clientStatID)!=1) THEN
      SET statusCode=4;
      LEAVE root;
    END IF;
  END IF;
  
  SELECT tournament_player_status_id INTO doesExist FROM gaming_tournament_player_statuses WHERE client_stat_id = clientStatID AND tournament_id=tournamentID;
  
  IF doesExist IS NULL THEN
    INSERT INTO gaming_tournament_player_statuses (tournament_id,client_stat_id,currency_id,total_bet,total_win,rounds,score,opted_in_date,is_active,last_updated_date)
    SELECT tournamentID,clientStatID,currency_id,0,0,0,0,NOW(),1,NOW()
    FROM gaming_client_stats
    WHERE client_stat_id = clientStatID;
  ELSE
    UPDATE gaming_tournament_player_statuses
    SET is_active=1
    WHERE client_stat_id = clientStatID AND tournament_id=tournamentID;
  END IF;
  
  SET tournamentStatusID = LAST_INSERT_ID();
  
  UPDATE gaming_tournaments SET num_participants = num_participants+1
  WHERE tournament_id = tournamentID;
  
  SET statusCode = 0 ;
  
END$$

DELIMITER ;

