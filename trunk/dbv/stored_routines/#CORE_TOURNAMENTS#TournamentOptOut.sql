
DROP procedure IF EXISTS `TournamentOptOut`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentOptOut`(tournamentID BIGINT, clientStatID BIGINT)
BEGIN
UPDATE gaming_tournament_player_statuses SET is_active=0
WHERE tournament_id=tournamentID AND client_stat_id= clientStatID ;
	
END$$

DELIMITER ;

