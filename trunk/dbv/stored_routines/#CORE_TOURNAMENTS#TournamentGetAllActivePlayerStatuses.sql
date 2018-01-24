DROP procedure IF EXISTS `TournamentGetAllActivePlayerStatuses`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentGetAllActivePlayerStatuses`(clientStatID BIGINT, activeOnly TINYINT(1))
BEGIN
  -- added previous rank and updated dates
  SELECT tournament_player_status_id, gaming_tournaments.tournament_id, gaming_tournaments.name AS tournament_name, player_statuses.total_bet, player_statuses.total_win, 
    player_statuses.rounds, player_statuses.score, player_statuses.rank, player_statuses.priority, player_statuses.opted_in_date, player_statuses.is_active,
    gaming_tournaments.tournament_date_start AS tournament_start_date,  gaming_tournaments.tournament_date_end AS tournament_end_date, gaming_tournaments.tournament_date_end<NOW() AS has_expired
	, player_statuses.last_updated_date, player_statuses.previous_rank, gaming_tournaments.last_temp_rank_update_date
  FROM gaming_tournament_player_statuses AS player_statuses  
  JOIN gaming_tournaments ON (player_statuses.client_stat_id = clientStatID AND (activeOnly=0 OR player_statuses.is_active=1)) AND
    player_statuses.tournament_id=gaming_tournaments.tournament_id AND (activeOnly=0 OR gaming_tournaments.tournament_date_end > NOW()); 
END$$

DELIMITER ;

