
DROP procedure IF EXISTS `GameRecommendationForGame`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameRecommendationForGame`()
BEGIN

DECLARE finished INTEGER DEFAULT 0;
DECLARE maxPlayers BIGINT DEFAULT 0;
DECLARE gameID BIGINT DEFAULT 0;
DECLARE gamesCursor CURSOR FOR SELECT DISTINCT gaming_operator_games.game_id FROM gaming_operator_games
							JOIN gaming_games ON gaming_operator_games.game_id = gaming_games.game_id-- should use value from gaming_operator_games
							WHERE gaming_operator_games.total_played > 0 AND gaming_games.is_launchable = 1; -- Get a cursor on those games which had any activity
DECLARE CONTINUE HANDLER 
FOR NOT FOUND SET finished = 1;


SELECT IFNULL(gs1.value_long, 100) as vl1
INTO maxPlayers
FROM gaming_settings gs1 	
WHERE gs1.name='RECOMMENDATIONS_GAME_GAMEREC_NUM_PLAYERS_MAX_PLAYED_GAME';

OPEN gamesCursor;

update_cache: LOOP
	SET finished = 0;
	FETCH gamesCursor INTO gameID;
	IF finished = 1 THEN
		LEAVE update_cache;
	END IF;
	
	INSERT INTO gaming_recommendations_result_cache_game (game_id, game_id_related, score, manufacturer_game_idf, last_updated) 
	SELECT gameID, Normalized.game_id, SUM(NormVal) AS WeightedSum, manufacturer_game_idf, NOW()
	FROM (SELECT Result.client_stat_id, Result.game_id, Result.amount, Total, IFNULL(Result.amount / Total,0) AS NormVal
		FROM gaming_recommendations_intermediate_cache_top_games Result
		LEFT JOIN
			(SELECT Top.client_stat_id, IFNULL(SUM(Top.amount),0) AS Total 
				 FROM gaming_recommendations_intermediate_cache_top_games Top 
				 LEFT JOIN ( SELECT client_stat_id FROM gaming_recommendations_intermediate_cache_top_games
							WHERE game_id = gameID
							ORDER BY preference, RAND() 
							LIMIT maxPlayers 
							) Clients ON Clients.client_stat_id = Top.client_stat_id -- This gives us those clients who played this game
				 WHERE Clients.client_stat_id IS NOT NULL 
				 GROUP BY client_stat_id
			) Inter ON Result.client_stat_id = Inter.client_stat_id -- This gives us the total of each player
			WHERE Total IS NOT NULL
			GROUP BY Result.client_stat_id, Result.game_id
		) Normalized   -- This normalizes the result.
	JOIN gaming_games ON Normalized.game_id = gaming_games.game_id AND gaming_games.is_launchable = 1
	WHERE Normalized.game_id != gameID
	GROUP BY Normalized.game_id 
	ORDER BY WeightedSum -- This adds up the normalized value giving the final result
	ON DUPLICATE KEY UPDATE score = VALUES(score); 

END LOOP update_cache;

CLOSE gamesCursor;


END$$

DELIMITER ;

