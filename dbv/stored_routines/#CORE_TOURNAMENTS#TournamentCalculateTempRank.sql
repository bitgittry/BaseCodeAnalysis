DROP procedure IF EXISTS `TournamentCalculateTempRank`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentCalculateTempRank`(tournamentID BIGINT)
root:BEGIN
  -- Added check on gaming_tournament_player_statuses.is_active=1
  -- Added update to last_temp_rank_update_date   

  DECLARE isFinalRanked TINYINT(1) DEFAULT 0;  

  SELECT ranked INTO isFinalRanked FROM gaming_tournaments WHERE tournament_id=tournamentID;

  IF (isFinalRanked) THEN
	LEAVE root;
  END IF;

  SET @rank = 0;
  UPDATE gaming_tournament_player_statuses 
  JOIN (
	  SELECT tournament_player_status_id, @rank := @rank:=@rank+1 AS rank
	  FROM
	  (
		SELECT tournament_player_status_id, score, rounds
		FROM gaming_tournament_player_statuses 
		WHERE gaming_tournament_player_statuses.tournament_id=tournamentID AND gaming_tournament_player_statuses.is_active=1
		ORDER BY score DESC, last_updated_date ASC
	  ) AS ordered_ranks
  ) AS ranks ON gaming_tournament_player_statuses.tournament_player_status_id = ranks.tournament_player_status_id
  SET gaming_tournament_player_statuses.previous_rank=IFNULL(gaming_tournament_player_statuses.rank, ranks.rank),
	  gaming_tournament_player_statuses.rank = ranks.rank
  WHERE gaming_tournament_player_statuses.rank IS NULL OR gaming_tournament_player_statuses.rank!=ranks.rank;
  
  UPDATE gaming_tournaments SET last_temp_rank_update_date=NOW() WHERE tournament_id=tournamentID; 

END root$$

DELIMITER ;

