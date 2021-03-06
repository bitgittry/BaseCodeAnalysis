
DROP procedure IF EXISTS `TournamentPlayerStatusSetTopPriorityForGame`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentPlayerStatusSetTopPriorityForGame`(clientStatID BIGINT, tournamentPlayerStatusID BIGINT, gameID BIGINT, OUT statusCode INT)
root: BEGIN
  
  
   
  DECLARE tournamentPlayerStatusIDCheck BIGINT DEFAULT -1;
  
  SELECT player_statuses.tournament_player_status_id INTO tournamentPlayerStatusIDCheck
  FROM gaming_tournament_player_statuses AS player_statuses
  JOIN gaming_tournaments ON
    player_statuses.tournament_player_status_id=tournamentPlayerStatusID AND player_statuses.client_stat_id=clientStatID AND player_statuses.is_active=1 AND
    player_statuses.tournament_id=gaming_tournaments.tournament_id AND gaming_tournaments.tournament_date_end>=NOW()
  LEFT JOIN gaming_tournament_games ON gaming_tournament_games.game_id=gameID AND player_statuses.tournament_id=gaming_tournament_games.tournament_id;
    
  IF (tournamentPlayerStatusIDCheck=-1) THEN
    SET statusCode=1;
    LEAVE root ;
  END IF;
  
  UPDATE gaming_tournament_player_statuses AS player_statuses
  SET player_statuses.priority=0
  WHERE player_statuses.tournament_player_status_id=tournamentPlayerStatusID;
  
  
  UPDATE gaming_tournament_player_statuses AS player_statuses
  JOIN gaming_tournaments ON
    player_statuses.client_stat_id=clientStatID AND player_statuses.tournament_player_status_id!=tournamentPlayerStatusID AND player_statuses.is_active=1 AND 
    player_statuses.tournament_id=gaming_tournaments.tournament_id AND gaming_tournaments.tournament_date_end>=NOW() 
  JOIN gaming_tournament_games ON gaming_tournament_games.game_id=gameID AND player_statuses.tournament_id=gaming_tournament_games.tournament_id
  SET player_statuses.priority=1
  WHERE player_statuses.priority=0;
  
  SET statusCode=0;
END root$$

DELIMITER ;

