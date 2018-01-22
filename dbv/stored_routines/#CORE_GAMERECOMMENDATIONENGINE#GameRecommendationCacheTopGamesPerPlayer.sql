DROP procedure IF EXISTS `GameRecommendationCacheTopGamesPerPlayer`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameRecommendationCacheTopGamesPerPlayer`()
BEGIN
 
DECLARE minutesLookBack BIGINT DEFAULT 87658;
DECLARE numGames BIGINT DEFAULT 87658;


SET @clientStatId = 0; 
SET @counter = 0;

SELECT IFNULL(gs1.value_long, 87658) as vl1, gs2.value_long as vl2
INTO minutesLookBack, numGames
FROM gaming_settings gs1 	
JOIN gaming_settings gs2 ON (gs2.name='RECOMMENDATIONS_GAME_NUM_TOP_GAMES')
WHERE gs1.name='RECOMMENDATIONS_GAME_LOOKBACK_PERIOD_MINUTES';

-- Params: Minutes look back, how far in the past we'll go
-- Params: numGames, the number of top games to consider
INSERT INTO gaming_recommendations_intermediate_cache_top_games (client_stat_id, game_id, amount, preference)
SELECT clientStat, gameID, amountScore, counters FROM (
	SELECT Players.client_stat_id AS clientStat, Players.game_id AS gameID, amountScore, IF(Players.client_stat_id != @clientStatId, @counter := 1, @counter := @counter + 1) AS num, @counter AS counters, IF(Players.client_stat_id != @clientStatId, @clientStatId := Players.client_stat_id, 1), @clientStatId
	FROM (SELECT agg.client_stat_id, agg.game_id, SUM(agg.bet_total) AS amountScore
		  FROM gaming_game_transactions_aggregation_player_game agg 
		  JOIN gaming_query_date_interval_types ON gaming_query_date_interval_types.name='Hourly'
		  JOIN gaming_query_date_intervals ON gaming_query_date_intervals.date_from BETWEEN DATE_SUB(NOW(), INTERVAL minutesLookBack MINUTE) AND NOW() AND agg.date_from BETWEEN gaming_query_date_intervals.date_from AND gaming_query_date_intervals.date_to
		  AND gaming_query_date_interval_types.query_date_interval_type_id=gaming_query_date_intervals.query_date_interval_type_id
		  GROUP BY client_stat_id, game_id
		  ORDER BY agg.client_stat_id, amountScore DESC
		) AS Players
	GROUP BY clientStat, gameID
	HAVING counters < numGames
	ORDER BY clientStat, gameID ASC, amountScore DESC) AS Result
ON DUPLICATE KEY UPDATE amount = amountScore;

END$$

DELIMITER ;

