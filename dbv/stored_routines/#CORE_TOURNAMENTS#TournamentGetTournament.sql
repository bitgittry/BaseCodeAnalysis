DROP procedure IF EXISTS `TournamentGetTournament`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentGetTournament`(tournamentID BIGINT)
BEGIN
    -- Added player selection and tournament type

    SELECT tournament_id, gaming_tournaments.name, gaming_tournaments.display_name, gaming_tournaments.tournament_type_id,
           tournament_date_start, tournament_date_end, leaderboard_date_start, leaderboard_date_end,
           gaming_tournaments.player_selection_id, selections.name AS player_selection_name, qualify_min_rounds, score_types.tournament_score_type_id, score_types.name AS score_type,
           score_num_rounds, num_prizes, stake_profit_percentage, num_participants,
           num_qualified_participants, total_rounds, tournament_gross, tournament_profit,
           gaming_tournaments.currency_id, gaming_tournaments.is_active, gaming_tournaments.is_hidden, gaming_tournaments.bonus_rule_id,
           prize_type, automatic_award_prize, wager_req_real_only,
           currency_profile_id,game_weight_profile_id,sb_weight_profile_id, tournament_types.name AS tournament_type_name
    FROM gaming_tournaments
		JOIN gaming_tournament_score_types AS score_types
			ON gaming_tournaments.tournament_score_type_id = score_types.tournament_score_type_id
		JOIN gaming_player_selections AS selections
			ON gaming_tournaments.player_selection_id = selections.player_selection_id
		JOIN gaming_tournament_types AS tournament_types
			ON gaming_tournaments.tournament_type_id = tournament_types.tournament_type_id
    WHERE tournament_id = tournamentID;

    SELECT game_id
    FROM   gaming_tournament_games
    WHERE  tournament_id = tournamentID;

    SELECT gaming_currency.currency_id, gaming_currency.currency_code, min_bet
    FROM   gaming_tournament_wager_restrictions
           JOIN gaming_currency ON gaming_tournament_wager_restrictions.currency_id = gaming_currency.currency_id
    WHERE  tournament_id = tournamentID;

    SELECT place, percentage
    FROM   gaming_tournament_share_place_percentage
    WHERE  tournament_id = tournamentID;

    SELECT tournament_prize_id, prize_position, wager_requirement_multiplier
    FROM   gaming_tournament_prizes
    WHERE  tournament_id = tournamentID;

    SELECT gaming_tournament_prizes.tournament_prize_id, gaming_currency.currency_id, gaming_currency.currency_code, amount
    FROM   gaming_tournament_prize_amounts
           JOIN gaming_tournament_prizes
             ON gaming_tournament_prizes.tournament_prize_id = gaming_tournament_prize_amounts.tournament_prize_id
           JOIN gaming_currency ON gaming_tournament_prize_amounts.currency_id = gaming_currency.currency_id
    WHERE  tournament_id = tournamentID;

  END$$

DELIMITER ;

