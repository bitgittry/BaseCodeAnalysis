DROP procedure IF EXISTS `SportsBookGetPlayerBetHistory`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `SportsBookGetPlayerBetHistory`(clientStatID BIGINT, startDate DATETIME, endDate DATETIME)
BEGIN
-- optimized
SET @client_stat_id=clientStatID;
SET @start_date=startDate;
SET @end_date=endDate;

(
SELECT 0 AS multiple, gaming_game_rounds.game_round_id, gaming_sb_bets.transaction_ref, gaming_game_rounds.date_time_start AS date_time, gaming_sb_bet_types.name AS channel, gaming_sb_sports.name AS sport, gaming_sb_groups.name AS `group`, gaming_sb_events.name AS event, gaming_sb_markets.name AS market, gaming_sb_selections.name AS selection,
  'Single' AS bet_type, gaming_sb_bet_singles.odd AS odds, ROUND(gaming_game_rounds.bet_real/100,2) AS bet_real, ROUND((gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked)/100, 2) AS bet_bonus, ROUND(gaming_game_rounds.win_real/100,2) AS win_real, ROUND((gaming_game_rounds.win_bonus+gaming_game_rounds.win_bonus_win_locked)/100,2) AS win_bonus, 
  IF(gaming_game_rounds.is_round_finished=0,'Open',IF(gaming_game_rounds.win_total>0,'Won','Lost')) AS status, gaming_sb_bet_singles.bet_ref, ROUND(balance_real_before/100, 2) AS balance_real_before,
  ROUND(balance_bonus_before/100,2) AS balance_bonus_before, ROUND(loyalty_points,2) AS loyalty_points, ROUND(loyalty_points_bonus,2) AS loyalty_points_bonus
FROM gaming_game_rounds  FORCE INDEX (player_date_time_start)
JOIN gaming_sb_selections ON gaming_game_rounds.sb_extra_id=gaming_sb_selections.sb_selection_id
JOIN gaming_sb_sports ON gaming_sb_selections.sb_sport_id=gaming_sb_sports.sb_sport_id
JOIN gaming_sb_groups ON gaming_sb_selections.sb_group_id=gaming_sb_groups.sb_group_id
JOIN gaming_sb_events ON gaming_sb_selections.sb_event_id=gaming_sb_events.sb_event_id
JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
JOIN gaming_sb_bet_singles ON gaming_sb_bet_singles.sb_bet_id=gaming_game_rounds.sb_bet_id AND gaming_sb_bet_singles.sb_selection_id=gaming_game_rounds.sb_extra_id
JOIN gaming_sb_bets ON gaming_game_rounds.sb_bet_id=gaming_sb_bets.sb_bet_id
LEFT JOIN gaming_sb_bet_types ON gaming_sb_bet_singles.sb_bet_type=gaming_sb_bet_types.code
WHERE gaming_game_rounds.client_stat_id=@client_stat_id AND gaming_game_rounds.date_time_start BETWEEN @start_date AND @end_date AND gaming_game_rounds.game_round_type_id=4   
)
UNION
(
SELECT 1 AS multiple, gaming_game_rounds.game_round_id, gaming_sb_bets.transaction_ref, gaming_game_rounds.date_time_start AS date_time, IF(COUNT(DISTINCT gaming_sb_bet_multiples_singles.sb_bet_type)=1, gaming_sb_bet_types.name, '') AS channel, IF(COUNT(DISTINCT gaming_sb_sports.sb_sport_id)=1, gaming_sb_sports.name, '') AS sport, 
  IF(COUNT(DISTINCT gaming_sb_groups.sb_group_id)=1, gaming_sb_groups.name, '') AS `group`, IF(COUNT(DISTINCT gaming_sb_events.sb_event_id)=1, gaming_sb_events.name, '') AS event, IF(COUNT(DISTINCT gaming_sb_markets.sb_market_id)=1, gaming_sb_markets.name, '') AS market, '' AS selection,
  gaming_sb_multiple_types.name AS bet_type, gaming_sb_bet_multiples.odd AS odds, ROUND(gaming_game_rounds.bet_real/100,2) AS bet_real, ROUND((gaming_game_rounds.bet_bonus+gaming_game_rounds.bet_bonus_win_locked)/100, 2) AS bet_bonus, ROUND(gaming_game_rounds.win_real/100,2) AS win_real, ROUND((gaming_game_rounds.win_bonus+gaming_game_rounds.win_bonus_win_locked)/100,2) AS win_bonus, 
  IF(gaming_game_rounds.is_round_finished=0,'Open',IF(gaming_game_rounds.win_total>0,'Won','Lost')) AS status, gaming_sb_bet_multiples.bet_ref, ROUND(balance_real_before/100, 2) AS balance_real_before,
  ROUND(balance_bonus_before/100,2) AS balance_bonus_before, ROUND(loyalty_points,2) AS loyalty_points, ROUND(loyalty_points_bonus,2) AS loyalty_points_bonus
FROM gaming_game_rounds  FORCE INDEX (player_date_time_start)
JOIN gaming_sb_multiple_types ON gaming_game_rounds.sb_extra_id=gaming_sb_multiple_types.sb_multiple_type_id
JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_id=gaming_game_rounds.sb_bet_id AND gaming_sb_bet_multiples.sb_multiple_type_id=gaming_game_rounds.sb_extra_id
JOIN gaming_sb_bet_multiples_singles ON gaming_sb_bet_multiples.sb_bet_multiple_id=gaming_sb_bet_multiples_singles.sb_bet_multiple_id
JOIN gaming_sb_selections ON gaming_sb_bet_multiples_singles.sb_selection_id=gaming_sb_selections.sb_selection_id
JOIN gaming_sb_sports ON gaming_sb_selections.sb_sport_id=gaming_sb_sports.sb_sport_id
JOIN gaming_sb_groups ON gaming_sb_selections.sb_group_id=gaming_sb_groups.sb_group_id
JOIN gaming_sb_events ON gaming_sb_selections.sb_event_id=gaming_sb_events.sb_event_id
JOIN gaming_sb_markets ON gaming_sb_selections.sb_market_id=gaming_sb_markets.sb_market_id
JOIN gaming_sb_bets ON gaming_game_rounds.sb_bet_id=gaming_sb_bets.sb_bet_id
LEFT JOIN gaming_sb_bet_types ON gaming_sb_bet_multiples_singles.sb_bet_type=gaming_sb_bet_types.code
WHERE gaming_game_rounds.client_stat_id=@client_stat_id AND gaming_game_rounds.date_time_start BETWEEN @start_date AND @end_date AND gaming_game_rounds.game_round_type_id=5   
GROUP BY gaming_game_rounds.game_round_id
)
ORDER BY game_round_id DESC;

END$$

DELIMITER ;

