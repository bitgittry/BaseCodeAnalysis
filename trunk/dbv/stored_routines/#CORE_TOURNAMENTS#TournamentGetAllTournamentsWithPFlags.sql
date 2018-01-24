DROP procedure IF EXISTS `TournamentGetAllTournamentsWithPFlags`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentGetAllTournamentsWithPFlags`(clientStatID BIGINT, onlyIfInSelection TINYINT(1))
BEGIN
	-- Added player selection and tournament type

    CALL PlayerSelectionUpdatePlayerCacheTournament(clientStatID);

    SET @curDateTemp = NOW();

    SELECT gaming_tournaments.tournament_id, gaming_tournaments.name, gaming_tournaments.display_name, gaming_tournaments.tournament_type_id,
           tournament_date_start, tournament_date_end, leaderboard_date_start, leaderboard_date_end,
           gaming_tournaments.player_selection_id, selections.name AS player_selection_name, qualify_min_rounds, score_types.tournament_score_type_id, score_types.name AS score_type,
           score_num_rounds, num_prizes, stake_profit_percentage, num_participants,
           gaming_tournaments.num_qualified_participants, gaming_tournaments.total_rounds, gaming_tournaments.tournament_gross, gaming_tournaments.tournament_profit,
           gaming_tournaments.currency_id, gaming_tournaments.is_active, gaming_tournaments.is_hidden, gaming_tournaments.bonus_rule_id,
           prize_type, automatic_award_prize, wager_req_real_only,
           currency_profile_id,game_weight_profile_id,sb_weight_profile_id, tournament_types.name AS tournament_type_name
           , IFNULL(cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_tournaments.player_selection_id, clientStatID)) AS is_player_in_selection
           , IF(player_status.tournament_player_status_id IS NULL, 0, 1) has_player_status
    FROM   gaming_tournaments
           JOIN gaming_tournament_score_types AS score_types
             ON gaming_tournaments.tournament_score_type_id = score_types.tournament_score_type_id
		   JOIN gaming_player_selections AS selections
				ON gaming_tournaments.player_selection_id = selections.player_selection_id
			JOIN gaming_tournament_types AS tournament_types
				ON gaming_tournaments.tournament_type_id = tournament_types.tournament_type_id
           LEFT JOIN gaming_player_selections_player_cache AS cache
             ON gaming_tournaments.player_selection_id = cache.player_selection_id AND cache.client_stat_id = clientStatID
           LEFT JOIN gaming_tournament_player_statuses AS player_status
             ON player_status.client_stat_id = clientStatID AND gaming_tournaments.tournament_id = player_status.tournament_id AND
                player_status.is_active
    WHERE  gaming_tournaments.tournament_date_end >= @curDateTemp AND gaming_tournaments.is_active = 1 AND (onlyIfInSelection = 0
           OR IFNULL                                                                                        (cache.player_in_selection, PlayerSelectionIsPlayerInSelection(gaming_tournaments.player_selection_id, clientStatID))
           );
  END$$

DELIMITER ;

