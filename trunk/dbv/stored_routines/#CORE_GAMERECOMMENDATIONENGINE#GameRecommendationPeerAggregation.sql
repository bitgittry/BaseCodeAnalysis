
DROP procedure IF EXISTS `GameRecommendationPeerAggregation`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameRecommendationPeerAggregation`(isHourly TINYINT(1), clientStatId BIGINT)
BEGIN
 
DECLARE numHoursInactive, maxGames BIGINT DEFAULT 1460;

SELECT IFNULL(gs1.value_long, 1460) as vl1, IFNULL(gs2.value_long, 50) as vl2
INTO numHoursInactive, maxGames
FROM gaming_settings gs1 	
JOIN gaming_settings gs2 ON (gs2.name='RECOMMENDATIONS_GAME_GAMEREC_NUM_PLAYERS_MAX_PLAYED_GAME')
WHERE gs1.name='RECOMMENDATIONS_GAME_INACTIVE_PLAYERS_LOOKBACK_HOURS';


-- This query gives those players who need an update to their recommendation's cache associated with the closest players based
-- on the games others played.
SELECT DISTINCT top.client_stat_id AS basePlayer, bot.client_stat_id AS relatedPlayer, peer_game_activity_weight 
FROM gaming_recommendations_intermediate_cache_top_games top
JOIN ( SELECT game_id, client_stat_id 
	   FROM gaming_recommendations_intermediate_cache_top_games ORDER BY preference LIMIT maxGames) AS bot ON  bot.game_id = top.game_id AND bot.client_stat_id != top.client_stat_id
JOIN gaming_client_stats gcs ON top.client_stat_id = gcs.client_stat_id AND (gcs.last_played_date > DATE_SUB(NOW(), INTERVAL 1 HOUR) OR IF(isHourly, 0, (gcs.last_played_date > DATE_SUB(NOW(), INTERVAL numHoursInactive HOUR)))) AND (gcs.client_stat_id = clientStatId OR IF(clientStatId = 0, 1=1, 0)) 
JOIN gaming_clients ON gcs.client_id = gaming_clients.client_id
LEFT JOIN gaming_client_segments_players AS gcsp ON gcsp.client_id = gaming_clients.client_id AND gcsp.is_current
LEFT JOIN gaming_client_segments ON gcsp.client_segment_id = gaming_client_segments.client_segment_id
LEFT JOIN gaming_client_segment_groups gcsg ON gaming_client_segments.client_segment_group_id = gcsg.client_segment_group_id AND gcsg.name = 'RecommendationsSegmentGroup'
LEFT JOIN gaming_recommendations_profiles AS grp ON grp.client_segment_id = gcsp.client_segment_id AND grp.is_current
WHERE peer_game_activity_weight IS NOT NULL
ORDER BY basePlayer;

-- This query gives the normalized amounts for those games played by players
SELECT Result.client_stat_id, Result.game_id, Result.amount, Total, IFNULL(Result.amount / Total,0) AS NormVal
	FROM gaming_recommendations_intermediate_cache_top_games Result
	JOIN
		(SELECT Top.client_stat_id, Top.game_id, Top.amount, IFNULL(SUM(Top.amount),0) AS Total 
		FROM gaming_recommendations_intermediate_cache_top_games Top 		
		GROUP BY client_stat_id
		) Inter ON Result.client_stat_id = Inter.client_stat_id -- This gives us the total of each player
GROUP BY Result.client_stat_id, Result.game_id;

END$$

DELIMITER ;

