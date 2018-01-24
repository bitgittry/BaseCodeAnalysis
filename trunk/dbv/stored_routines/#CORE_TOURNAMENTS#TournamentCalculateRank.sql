DROP procedure IF EXISTS `TournamentCalculateRank`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentCalculateRank`(tournamentID BIGINT,OUT statusCode INT)
root:BEGIN
  -- Checking on @tournamentEndDate <= NOW() and @isFinalRanked=1  
  -- Removed rank checking for status code = 2 (Tournament is still active)
  -- Also updated rank updating. If the tournament is not ranked prizes will not be awarded

  DECLARE tournamentIDVar BIGINT DEFAULT -1;
  SET statusCode = 0;
  
  SELECT gaming_tournaments.tournament_id, tournament_date_end, ranked
  INTO tournamentIDVar, @tournamentEndDate, @isFinalRanked 
  FROM gaming_tournaments WHERE tournament_id=tournamentID 
  FOR UPDATE;
  
  IF (tournamentIDVar=-1) THEN
    SET statusCode =1;
    LEAVE root;
  END IF;
    
  IF (@tournamentEndDate >= NOW()) THEN
    SET statusCode =2;
    LEAVE root;
  END IF;
  
  SET @rank = 0;
  
  UPDATE gaming_tournament_player_statuses 
  JOIN (
    SELECT tournament_player_status_id, @rank := @rank:=@rank+1 AS rank
    FROM 
    (
      SELECT tournament_player_status_id ,gaming_tournament_player_statuses.score,gaming_tournament_player_statuses.rounds
      FROM gaming_tournament_player_statuses
      JOIN gaming_tournaments ON gaming_tournament_player_statuses.tournament_id=gaming_tournaments.tournament_id
      WHERE gaming_tournament_player_statuses.tournament_id=tournamentID
      ORDER BY IF(gaming_tournament_player_statuses.rounds<qualify_min_rounds, 0, score) DESC, last_updated_date ASC
    ) AS ranks
  ) AS ranks ON gaming_tournament_player_statuses.tournament_player_status_id = ranks.tournament_player_status_id
  SET gaming_tournament_player_statuses.rank = ranks.rank; 
  
  UPDATE gaming_tournaments SET ranked=1, is_active = 0 WHERE tournament_id=tournamentID;
  
END root$$

DELIMITER ;

