
DROP procedure IF EXISTS `GameRecommendationRetrieveGamesForGameResult`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameRecommendationRetrieveGamesForGameResult`(gameID BIGINT, numGames BIGINT, numRecommendedOnly BIGINT, platformTypeID INT)
BEGIN

DECLARE feedbackEnabled TINYINT(1);
DECLARE lastInsertedCounter, numRandomGames, numRandomGamesExpected BIGINT DEFAULT 0;

SELECT value_bool INTO feedbackEnabled FROM gaming_settings WHERE name = 'RECOMMENDATIONS_GAME_FEEDBACK_ENABLED';



-- Add to historical counter 
INSERT INTO gaming_recommendations_game_historical_counter (game_id, timestamp)
VALUES (gameID, NOW());
SET lastInsertedCounter = LAST_INSERT_ID(); 

SET @counter = 0;

-- Add to historical log 
INSERT INTO gaming_recommendations_game_historical (recommendation_game_historical_counter_id, game_id_related, rank, score, is_random)
SELECT lastInsertedCounter, game_id_related, @counter := @counter + 1, score, IF(score = -1, 1, 0)
FROM (
		SELECT cacheRes.game_id, game_id_related, score
		FROM gaming_recommendations_result_cache_game cacheRes
		JOIN gaming_games ON cacheRes.game_id_related = gaming_games.game_id AND is_launchable
        JOIN gaming_game_platform_types ON gaming_game_platform_types.game_id = gaming_games.game_id
		WHERE cacheRes.game_id = gameID AND gaming_game_platform_types.platform_type_id = platformTypeID
		ORDER BY score DESC
		LIMIT numRecommendedOnly

	) Recommended
LIMIT numGames;

SET numRandomGamesExpected = numGames-numRecommendedOnly;
SET numRandomGames = IF(@counter < numRecommendedOnly, numRandomGamesExpected + (numRecommendedOnly - @counter), numRandomGamesExpected);

INSERT INTO gaming_recommendations_game_historical (recommendation_game_historical_counter_id, game_id_related, rank, score, is_random)
SELECT lastInsertedCounter, game_id_related, @counter := @counter + 1, -1, 1
FROM
	(SELECT gaming_games.game_id AS game_id_related
		FROM gaming_games
		JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
        JOIN gaming_game_platform_types ON gaming_game_platform_types.game_id = gaming_games.game_id
		WHERE gaming_game_platform_types.platform_type_id = platformTypeID AND gaming_games.game_id NOT IN (SELECT game_id_related
							FROM gaming_recommendations_game_historical cacheRes
							WHERE recommendation_game_historical_counter_id = lastInsertedCounter) AND is_launchable
	) Random
LIMIT numRandomGames;

-- Return Result
SELECT grghc.game_id, game_id_related, score, gaming_games.name, gaming_games.manufacturer_game_idf,manufacturer_game_type, gaming_game_manufacturers.name AS manufacturerName, game_description, gaming_game_types.name AS gameTypeName, 
                    has_tournament, has_jackpot, has_minigame, options, gaming_games.date_added, gaming_game_categories_games.game_category_id, manufacturer_game_launch_type, has_play_for_fun   
FROM gaming_recommendations_game_historical grgh
JOIN gaming_recommendations_game_historical_counter grghc ON grgh.recommendation_game_historical_counter_id = grghc.recommendation_game_historical_counter_id
JOIN gaming_games ON grgh.game_id_related = gaming_games.game_id AND gaming_games.is_launchable = 1
LEFT JOIN gaming_game_types ON gaming_games.game_type_id = gaming_game_types.game_type_id 
JOIN gaming_game_manufacturers ON gaming_game_manufacturers.is_active=1 AND gaming_games.game_manufacturer_id=gaming_game_manufacturers.game_manufacturer_id
LEFT JOIN gaming_game_categories_games ON gaming_games.game_id = gaming_game_categories_games.game_id
WHERE grghc.game_id = gameID AND grgh.recommendation_game_historical_counter_id = lastInsertedCounter
ORDER BY score DESC, RAND() 
LIMIT numGames;

IF (!feedbackEnabled) THEN
	DELETE FROM gaming_recommendations_game_historical
	WHERE recommendation_game_historical_counter_id=lastInsertedCounter;

	DELETE FROM gaming_recommendations_game_historical_counter
	WHERE recommendation_game_historical_counter_id=lastInsertedCounter;
END IF;

END$$

DELIMITER ;

