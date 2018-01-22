DROP procedure IF EXISTS `TournamentsProcessBets`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `TournamentsProcessBets`(gamePlayProcessCounterID BIGINT)
BEGIN

  
  SET @round_row_count=1;
  SET @game_round_id=-1;
  SET @max_contributions_per_round= 1; 
  
  SET @tstatus_row_count=1;
  SET @tournament_status_id=-1;
  
  SET @tournaments = '';
  
  
  INSERT INTO gaming_game_rounds_tournament_contributions(game_round_id, tournament_id, timestamp, tournament_player_status_id, bet, win, loss, round_contribute_num, game_play_process_counter_id, bet_real, win_real)
  SELECT game_round_id, tournament_id, NOW(), tournament_player_status_id, bet, win, loss, tstatus_row_count, gamePlayProcessCounterID, betReal, winReal  FROM 
  (
    SELECT @tstatus_row_count:=IF(tournament_player_status_id!=@tournament_status_id, newRounds, @tstatus_row_count+1) AS tstatus_row_count, @tournament_status_id:=IF(tournament_player_status_id!=@tournament_status_id, tournament_player_status_id, @tournament_status_id), resultSet.*
    FROM 
    (
      SELECT tournament_id, game_round_id, tournament_player_status_id, bet, win, loss,newRounds, betReal, winReal
      FROM
      (
        SELECT 
        @round_row_count:=IF(game_round_id!=@game_round_id, 1, @round_row_count+1) AS round_row_count, @game_round_id:=IF(game_round_id!=@game_round_id, game_round_id, @game_round_id), newRounds.*
        FROM
        (
          SELECT gaming_tournaments.tournament_id,gaming_game_rounds.game_round_id, tournament_player_status_id, 
            ROUND(IF (wager_req_real_only=0,bet_total,bet_real)/gaming_game_rounds.exchange_rate, 2) AS bet, ROUND(IF (wager_req_real_only=0,win_total,win_real)/gaming_game_rounds.exchange_rate, 2) AS win, 
            ROUND(IF (wager_req_real_only=0,bet_total-win_total,bet_real-win_real)/gaming_game_rounds.exchange_rate, 2) AS loss,
            gaming_tournament_player_statuses.rounds+1 AS newRounds, bet_real/gaming_game_rounds.exchange_rate AS betReal, win_real/gaming_game_rounds.exchange_rate AS winReal
          FROM gaming_game_plays_process_counter_rounds
          JOIN gaming_game_rounds ON gaming_game_rounds.game_round_id = gaming_game_plays_process_counter_rounds.game_round_id
          JOIN gaming_tournament_player_statuses ON gaming_tournament_player_statuses.client_stat_id = gaming_game_rounds.client_stat_id
          JOIN gaming_tournaments ON gaming_tournament_player_statuses.tournament_id = gaming_tournaments.tournament_id AND gaming_tournaments.is_active=1 AND gaming_game_rounds.date_time_start BETWEEN tournament_date_start AND tournament_date_end
          JOIN gaming_tournament_games ON gaming_tournament_games.tournament_id = gaming_tournaments.tournament_id AND gaming_tournament_games.game_id = gaming_game_rounds.game_id
	        LEFT JOIN gaming_tournament_wager_restrictions ON gaming_tournament_wager_restrictions.tournament_id=gaming_tournament_player_statuses.tournament_id AND gaming_tournament_player_statuses.currency_id=gaming_tournament_wager_restrictions.currency_id
          WHERE game_play_process_counter_id = gamePlayProcessCounterID 
			  AND gaming_tournament_player_statuses.is_active=1 
			  AND ROUND(IF(wager_req_real_only=0,bet_total,bet_real)/gaming_game_rounds.exchange_rate,2)>=IFNULL(min_bet,0) 		 
          ORDER BY game_round_id, gaming_tournament_player_statuses.priority, gaming_tournament_player_statuses.opted_in_date
        ) AS newRounds
      ) AS newRounds 
      WHERE round_row_count<=@max_contributions_per_round
      ORDER BY tournament_player_status_id,game_round_id
    ) AS resultSet
  ) AS resultSet
  ON DUPLICATE KEY UPDATE timestamp=VALUES(timestamp), bet=VALUES(bet), win=VALUES(win), loss=VALUES(loss), 
	round_contribute_num=VALUES(round_contribute_num), game_play_process_counter_id=VALUES(game_play_process_counter_id), bet_real=VALUES(bet_real), win_real=VALUES(win_real);
  
  
  UPDATE gaming_tournament_player_statuses
  JOIN (
    SELECT tournament_player_status_id, SUM(bet) AS sumBet, SUM(win) AS sumWin, COUNT(bet) AS countBet, SUM(bet_real) AS betReal, SUM(win_real) AS winReal
    FROM gaming_game_rounds_tournament_contributions
    WHERE game_play_process_counter_id = gamePlayProcessCounterID
    GROUP BY tournament_player_status_id
  ) AS updatesPlayerStatuses ON updatesPlayerStatuses.tournament_player_status_id = gaming_tournament_player_statuses.tournament_player_status_id
  JOIN gaming_tournaments ON gaming_tournaments.tournament_id=gaming_tournament_player_statuses.tournament_id
  JOIN gaming_tournament_score_types ON gaming_tournament_score_types.tournament_score_type_id = gaming_tournaments.tournament_score_type_id
     SET
      total_bet = total_bet + IFNULL(sumBet,0),
      total_win = total_win + IFNULL(sumWin,0),
      score = GREATEST(0, IFNULL(CASE
        WHEN gaming_tournament_score_types.name = 'BestSingleRoundNetWin' THEN
          (SELECT GREATEST(IFNULL(MAX(win-bet),0),score) FROM gaming_game_rounds_tournament_contributions
          WHERE gaming_game_rounds_tournament_contributions.tournament_player_status_id=gaming_tournament_player_statuses.tournament_player_status_id
          AND game_play_process_counter_id = gamePlayProcessCounterID
          GROUP BY tournament_player_status_id)
        WHEN gaming_tournament_score_types.name = 'BestOverallNetWin' THEN
          
          total_win + IFNULL(sumWin,0) -total_bet - IFNULL(sumBet,0)
        WHEN gaming_tournament_score_types.name = 'BestOverallPayoutFactor' THEN
          
          ((total_win + IFNULL(sumWin,0)) /  (total_bet + IFNULL(sumBet,0)))*10000
        WHEN gaming_tournament_score_types.name = 'BestEqualizedPayoutFactor' THEN
          (SELECT (IFNULL(SUM(win/bet),0)+ ((score/10000) * rounds))/(rounds + IFNULL(countBet,0)) FROM gaming_game_rounds_tournament_contributions
          WHERE gaming_game_rounds_tournament_contributions.tournament_player_status_id=gaming_tournament_player_statuses.tournament_player_status_id
          AND game_play_process_counter_id = gamePlayProcessCounterID
          GROUP BY tournament_player_status_id)*10000
        WHEN gaming_tournament_score_types.name = 'BestConseqRoundsNetWin' THEN
          (SELECT GREATEST(MAX(NetWin),score)
           FROM (
              SELECT AVG(r2.win-r2.bet) AS NetWin,r.tournament_player_status_id,r.round_contribute_num
              FROM gaming_game_rounds_tournament_contributions AS r
              JOIN gaming_game_rounds_tournament_contributions AS r2 ON r.tournament_player_status_id = r2.tournament_player_status_id
              JOIN gaming_tournaments ON r.tournament_id = gaming_tournaments.tournament_id
              WHERE 
                    r2.round_contribute_num <=r.round_contribute_num AND
                    r2.round_contribute_num > r.round_contribute_num - score_num_rounds AND
                    r.game_play_process_counter_id = gamePlayProcessCounterID AND
                    r.round_contribute_num>=score_num_rounds
              GROUP BY  r.tournament_player_status_id,r.round_contribute_num
            ) AS summations
          WHERE summations.tournament_player_status_id=gaming_tournament_player_statuses.tournament_player_status_id)
        WHEN gaming_tournament_score_types.name = 'BestConseqRoundsEqPayoutFactor' THEN
           (SELECT GREATEST(MAX(NetWin)*10000,score)
           FROM (
              SELECT AVG(r2.win/r2.bet) AS NetWin,r.tournament_player_status_id,r.round_contribute_num
              FROM gaming_game_rounds_tournament_contributions AS r
              JOIN gaming_game_rounds_tournament_contributions AS r2 ON r.tournament_player_status_id = r2.tournament_player_status_id
              JOIN gaming_tournaments ON r.tournament_id = gaming_tournaments.tournament_id
              WHERE
                    r2.round_contribute_num <=r.round_contribute_num AND
                    r2.round_contribute_num > r.round_contribute_num - score_num_rounds AND 
                    r.game_play_process_counter_id = gamePlayProcessCounterID AND
                    r.round_contribute_num>=score_num_rounds
              GROUP BY  r.tournament_player_status_id,r.round_contribute_num
            ) AS summations
          WHERE summations.tournament_player_status_id=gaming_tournament_player_statuses.tournament_player_status_id)
        WHEN gaming_tournament_score_types.name = 'MostRounds' THEN
          score+ IFNULL(countBet,0)
        ELSE
          score
        END,0)),
      rounds = rounds + IFNULL(countBet,0),
      total_win_real = total_win_real + IFNULL(winReal,0),
      total_bet_real = total_bet_real + IFNULL(betReal,0),
      last_updated_date = NOW();
        
  UPDATE gaming_tournaments 
  JOIN (
      SELECT SUM(total_win_real) AS winReal, SUM(total_bet_real) AS betReal, SUM(gaming_tournament_player_statuses.rounds) AS sumRounds, gaming_tournament_player_statuses.tournament_id
      FROM gaming_tournament_player_statuses
      WHERE gaming_tournament_player_statuses.tournament_id IN (
        SELECT tournament_id FROM gaming_game_rounds_tournament_contributions 
        WHERE game_play_process_counter_id = gamePlayProcessCounterID 
        GROUP BY tournament_id )
      GROUP BY tournament_id
  ) AS aggregations ON aggregations.tournament_id= gaming_tournaments.tournament_id
  SET tournament_gross = aggregations.betReal - aggregations.winReal,
      tournament_profit= aggregations.betReal - aggregations.winReal,
      total_rounds = sumRounds
  WHERE is_active=1 AND is_hidden=0;
  
END$$

DELIMITER ;

