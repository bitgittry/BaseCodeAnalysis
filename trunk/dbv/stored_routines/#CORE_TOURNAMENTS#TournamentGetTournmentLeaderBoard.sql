
DROP procedure IF EXISTS `TournamentGetTournmentLeaderBoard`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentGetTournmentLeaderBoard`(TournamentID BIGINT, PageNum INT, AmountPerPage INT)
BEGIN
  -- Added currency, prize_amount, stake_prize_amount, awarded_prize_amount
  -- Converting stake_prize_amount with the currenct exchange rate or the exchange rate set in the tournament
  DECLARE FromRank, ToRank INT DEFAULT 0;
  DECLARE isRanked TINYINT(1) DEFAULT 0;
  DECLARE tournamentProfit, stakeProfitPercentage DECIMAL(18,5) DEFAULT 0;  
  DECLARE operatorID BIGINT DEFAULT 0;
  DECLARE numOptedIn BIGINT DEFAULT 0 ;

  SELECT operator_id INTO operatorID FROM gaming_operators WHERE is_main_operator LIMIT 1;

  SET @firstResult=(PageNum-1)*AmountPerPage; 
  SET FromRank = @firstResult + 1;
  SET ToRank = @firstResult + AmountPerPage;
  
  SELECT ranked, tournament_profit, IFNULL(stake_profit_percentage,0) INTO isRanked, tournamentProfit, stakeProfitPercentage FROM gaming_tournaments WHERE tournament_id=TournamentID;

  SELECT COUNT(1) AS players_opted_in INTO numOptedIn
  FROM gaming_tournament_player_statuses WHERE tournament_id = TournamentID AND is_active;

  SET tournamentProfit=IF(tournamentProfit>0, tournamentProfit, 0);

  -- Return tournament stats
  SELECT numOptedIn AS players_opted_in, isRanked AS is_ranked, stakeProfitPercentage AS stake_profit_percentage, tournamentProfit AS tournament_profit,
		 gaming_tournament_score_types.name AS score_type, gaming_tournaments.qualify_min_rounds, gaming_tournaments.prize_type
  FROM gaming_tournaments 
  JOIN gaming_tournament_score_types ON gaming_tournaments.tournament_score_type_id=gaming_tournament_score_types.tournament_score_type_id
  WHERE gaming_tournaments.tournament_id = TournamentID;

  -- Return prizes per currency
  SELECT gaming_currency.currency_code, SUM(gaming_tournament_prize_amounts.amount) AS total_prize_amount
  FROM gaming_tournament_prizes
  JOIN gaming_tournament_prize_amounts ON gaming_tournament_prizes.tournament_prize_id=gaming_tournament_prize_amounts.tournament_prize_id
  JOIN gaming_currency ON gaming_tournament_prize_amounts.currency_id=gaming_currency.currency_id
  WHERE gaming_tournament_prizes.tournament_id=TournamentID
  GROUP BY gaming_currency.currency_id;

  -- Return leaderboard
  IF (isRanked=0) THEN
    SET @rank = 0;
    SELECT PRanked.rank, PRanked.score, PRanked.rounds, PRanked.total_bet, PRanked.total_win,
	  PRanked.platform_type, PRanked.client_id, PRanked.client_stat_id, PRanked.first_name, PRanked.nickname, PRanked.sign_up_date, PRanked.gender, 
	      PRanked.country_code, PRanked.country_name, PRanked.city, PRanked.language_code, PRanked.vip_level, PRanked.vip_level_id, PRanked.affiliate_code,
		  PRanked.currency_code, gaming_tournament_prize_amounts.amount AS prize_amount, ROUND(tournamentProfit*stakeProfitPercentage*share_percentage.percentage*IFNULL(IFNULL(gaming_tournament_currencies.exchange_rate, gaming_operator_currency.exchange_rate),0), 5) AS stake_prize_amount, PRanked.awarded_prize_amount
    FROM 
    (
    	SELECT @rank := @rank+1 AS rank,temp.* 
		FROM(
				SELECT gtps.score, gtps.rounds, gtps.total_bet, gtps.total_win,
					gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
					gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code,
					gaming_currency.currency_id, gaming_currency.currency_code,  gtps.awarded_prize_amount
				FROM gaming_tournament_player_statuses AS gtps
				JOIN gaming_client_stats ON gtps.client_stat_id = gaming_client_stats.client_stat_id
				JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
				JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
				LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
				LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
				LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
				LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
				LEFT JOIN sessions_main ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.extra2_id=gaming_client_stats.client_stat_id AND sessions_main.is_latest
				LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
				WHERE gtps.tournament_id=TournamentID AND gtps.is_active
				ORDER BY gtps.score DESC, gtps.last_updated_date 
		) AS temp
    ) AS PRanked
	LEFT JOIN gaming_tournament_prizes ON gaming_tournament_prizes.tournament_id=TournamentID AND gaming_tournament_prizes.prize_position=PRanked.rank
	LEFT JOIN gaming_tournament_prize_amounts ON gaming_tournament_prizes.tournament_prize_id=gaming_tournament_prize_amounts.tournament_prize_id AND gaming_tournament_prize_amounts.currency_id=PRanked.currency_id
    LEFT JOIN gaming_tournament_share_place_percentage AS share_percentage ON share_percentage.tournament_id=TournamentID AND share_percentage.place=PRanked.rank
	LEFT JOIN gaming_tournament_currencies ON gaming_tournament_currencies.tournament_id=TournamentID AND PRanked.currency_id=gaming_tournament_currencies.currency_id
	LEFT JOIN gaming_operator_currency ON PRanked.currency_id=gaming_operator_currency.currency_id AND gaming_operator_currency.operator_id=operatorID
	WHERE PRanked.rank BETWEEN FromRank AND ToRank;
  ELSE
    SELECT IFNULL(gtps.rank, 1000000) AS rank, gtps.score, gtps.rounds, gtps.total_bet, gtps.total_win,
	  gaming_platform_types.platform_type, gaming_clients.client_id, gaming_client_stats.client_stat_id, gaming_clients.name AS first_name, gaming_clients.nickname, gaming_clients.sign_up_date, gaming_clients.gender, 
	  gaming_countries.country_code, gaming_countries.name AS country_name, clients_locations.city, gaming_languages.language_code, gaming_clients.vip_level, gaming_clients.vip_level_id, gaming_affiliates.affiliate_code,
	  gaming_currency.currency_code, gaming_tournament_prize_amounts.amount AS prize_amount, ROUND(tournamentProfit*stakeProfitPercentage*share_percentage.percentage*IFNULL(IFNULL(gaming_tournament_currencies.exchange_rate, gaming_operator_currency.exchange_rate),0), 5) AS stake_prize_amount, gtps.awarded_prize_amount
    FROM gaming_tournament_player_statuses AS gtps
    JOIN gaming_client_stats ON gtps.client_stat_id = gaming_client_stats.client_stat_id
	JOIN gaming_currency ON gaming_client_stats.currency_id=gaming_currency.currency_id
    JOIN gaming_clients ON gaming_client_stats.client_id = gaming_clients.client_id
    LEFT JOIN clients_locations ON gaming_clients.client_id=clients_locations.client_id AND clients_locations.is_primary
	LEFT JOIN gaming_countries ON clients_locations.country_id=gaming_countries.country_id	
	LEFT JOIN gaming_languages ON gaming_clients.language_id=gaming_languages.language_id
	LEFT JOIN gaming_affiliates ON gaming_clients.affiliate_id=gaming_affiliates.affiliate_id
    LEFT JOIN sessions_main ON sessions_main.extra_id=gaming_clients.client_id AND sessions_main.extra2_id=gaming_client_stats.client_stat_id AND sessions_main.is_latest
    LEFT JOIN gaming_platform_types ON sessions_main.platform_type_id=gaming_platform_types.platform_type_id
	LEFT JOIN gaming_tournament_prizes ON gaming_tournament_prizes.tournament_id=TournamentID AND gaming_tournament_prizes.prize_position=gtps.rank
	LEFT JOIN gaming_tournament_prize_amounts ON gaming_tournament_prizes.tournament_prize_id=gaming_tournament_prize_amounts.tournament_prize_id AND gaming_tournament_prize_amounts.currency_id=gaming_currency.currency_id
	LEFT JOIN gaming_tournament_share_place_percentage AS share_percentage ON share_percentage.tournament_id=TournamentID AND share_percentage.place=gtps.rank
	LEFT JOIN gaming_tournament_currencies ON gaming_tournament_currencies.tournament_id=TournamentID AND gaming_client_stats.currency_id=gaming_tournament_currencies.currency_id
	LEFT JOIN gaming_operator_currency ON gaming_client_stats.currency_id=gaming_operator_currency.currency_id AND gaming_operator_currency.operator_id=operatorID
	WHERE (gtps.tournament_id=TournamentID AND gtps.is_active) AND (gtps.rank BETWEEN FromRank AND ToRank) AND gtps.rank IS NOT NULL 
    ORDER BY gtps.rank ASC;
  END IF;

END$$

DELIMITER ;

