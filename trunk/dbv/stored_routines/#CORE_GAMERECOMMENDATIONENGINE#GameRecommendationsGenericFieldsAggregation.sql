
DROP procedure IF EXISTS `GameRecommendationsGenericFieldsAggregation`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `GameRecommendationsGenericFieldsAggregation`(clientStatID BIGINT, isHourly TINYINT(1), logging TINYINT(1), OUT statusCode INT)
BEGIN

-- Status Code Values:
-- 1 = No entries in intermediate cache for top games per player.

DECLARE locationScoreLog, genderScoreLog, ageScoreLog, bonusCouponScoreLog DECIMAL(18,5) DEFAULT 0.0;
DECLARE gameIDLog BIGINT DEFAULT 0.0;
DECLARE numHoursInactive BIGINT DEFAULT 1460;

SET locationScoreLog = 0.0;
SET genderScoreLog = 0.0;
SET ageScoreLog = 0.0;
SET bonusCouponScoreLog = 0.0;
SET @counter = 0;
SET @countryID = 0;
SET @gender = 'A';
SET @age_range = 0; 
SET @size = 0;
SET statusCode = 0;


SELECT IFNULL(gs1.value_long, 1460) as vl1
INTO numHoursInactive
FROM gaming_settings gs1 	
WHERE gs1.name='RECOMMENDATIONS_GAME_INACTIVE_PLAYERS_LOOKBACK_HOURS';

SELECT COUNT(*) INTO @size FROM gaming_recommendations_intermediate_cache_top_games;

IF (@size > 0) THEN

	IF (clientStatID = 0) THEN 

		SELECT client_stat_id, gameId, ROUND(IFNULL((locationScore + genderScore + ageScore + bonusCouponScore),0.0),4) AS Score
		FROM (
		SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id, Result.game_id AS gameId, IFNULL(SUM(IF(Result.country_id IS NOT NULL, location_weight / score_order, 0)),0.0) AS locationScore, IFNULL(SUM(IF(Result.gender IS NOT NULL, gender_weight / score_order, 0)),0.0) AS genderScore,
				IFNULL(SUM(IF(Result.age_range_id IS NOT NULL, age_weight / score_order, 0)),0.0) AS ageScore, IFNULL(SUM(IF(Result.bonus_coupon_id IS NOT NULL, bonus_coupon_weight / score_order, 0)),0.0) AS bonusCouponScore  
		FROM gaming_clients 
		JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id AND (gaming_client_stats.last_played_date > DATE_SUB(NOW(), INTERVAL 1 HOUR) OR IF(isHourly, 0, (gaming_client_stats.last_played_date > DATE_SUB(NOW(), INTERVAL numHoursInactive HOUR))))
		JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id
		LEFT JOIN (
		-- COUNTRY --
		SELECT country_id,NULL AS gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max,  NULL AS bonus_coupon_id, game_id, amountScore, score_order 
		FROM (SELECT country_id, Intermediate.game_id, amountScore, IF(country_id != @countryID, @counter := 1, @counter := @counter + 1) AS orderNum, @counter AS score_order, IF(country_id != @countryID, @countryID := country_id, 0)
			FROM (SELECT cl.country_id, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id -- , location_weight As Weight
					FROM gaming_recommendations_intermediate_cache_top_games ggtapg
					JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
					JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
					JOIN clients_locations AS cl ON cl.client_id = gc.client_id AND cl.is_primary
					
					GROUP BY cl.country_id, game_id
					ORDER BY cl.country_id, amountScore DESC
				 ) Intermediate
			) Result
		GROUP BY country_id, Result.game_id
		UNION 
		-- GENDER --
		SELECT NULL AS country_id, gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max,  NULL AS bonus_coupon_id, game_id, amountScore, score_order 
		FROM (SELECT gender, Intermediate.game_id, amountScore, IF(gender != @gender, @counter := 1, @counter := @counter + 1) AS orderNum, @counter AS score_order, IF(gender != @gender, @gender := gender, 0)
			FROM (SELECT gender, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id 
					FROM gaming_recommendations_intermediate_cache_top_games ggtapg
					JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
					JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
					GROUP BY gender, game_id
					ORDER BY gender, amountScore DESC
				 ) Intermediate
		) Result
		GROUP BY gender, Result.game_id
		UNION
		-- AGE --
		SELECT NULL AS country_id, NULL AS gender, age_range_id, age_min, age_max, NULL AS bonus_coupon_id, game_id, amountScore, score_order
		FROM (SELECT age_range_id, age_min, age_max, game_id, amountScore, score_order 
			FROM (SELECT age_range_id, age_min, age_max, Intermediate.game_id, amountScore, IF(age_range_id != @age_range, @counter := 1, @counter := @counter + 1) AS orderNum,  @counter AS score_order, IF(age_range_id != @age_range, @age_range := age_range_id, 0)
				FROM (SELECT age_range_id, age_min, age_max, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id 
						FROM gaming_recommendations_intermediate_cache_top_games ggtapg
						JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
						JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
						JOIN gaming_recommendations_age_ranges AS grar ON DATE_FORMAT(NOW(), '%Y') - DATE_FORMAT(gc.dob, '%Y') - (DATE_FORMAT(NOW(), '00-%m-%d') < DATE_FORMAT(gc.dob, '00-%m-%d')) BETWEEN age_min AND age_max
						GROUP BY age_range_id, game_id
						ORDER BY age_range_id, amountScore DESC
					 ) Intermediate
				) Result
		) Result1
		GROUP BY age_range_id, Result1.game_id
		UNION
		-- Bonus Coupon --
		SELECT NULL AS country_id, NULL AS gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max, bonus_coupon_id, game_id, preference, 1 AS score_order
		FROM gaming_recommendations_games_bonus_coupon
		GROUP BY bonus_coupon_id, game_id)
		 Result ON gaming_clients.gender = Result.gender OR clients_locations.country_id = Result.country_id OR DATE_FORMAT(NOW(), '%Y') - DATE_FORMAT(gaming_clients.dob, '%Y') - (DATE_FORMAT(NOW(), '00-%m-%d') < DATE_FORMAT(gaming_clients.dob, '00-%m-%d')) BETWEEN Result.age_min AND Result.age_max 
					OR gaming_clients.bonus_coupon_id = Result.bonus_coupon_id

		JOIN gaming_client_segments_players AS gcsp ON gcsp.client_id = gaming_clients.client_id
		JOIN gaming_recommendations_profiles AS grp ON grp.client_segment_id = gcsp.client_segment_id AND grp.is_current
		GROUP BY client_stat_id, gameId
		ORDER BY client_stat_id, gameId
		) Done;

	ELSE  -- ------------------------------------------------------------------------------------------------------------------------------------

		IF(logging) THEN
			-- This is the same query as above but it is used on a single client and will include logging functions
			-- CREATE TEMPORARY TABLE IF NOT EXISTS log_temp_table (client_stat_id BIGINT, game_id BIGINT, location_score DECIMAL(18,5), gender_score DECIMAL(18,5), age_score DECIMAL(18,5), bonus_coupon_score DECIMAL(18,5))
			CREATE TEMPORARY TABLE IF NOT EXISTS log_temp_table 
			AS (
				SELECT client_stat_id, gameId, locationScore, genderScore, ageScore, bonusCouponScore, 0, NOW()   
				FROM (
				SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id, Result.game_id AS gameId, SUM(IF(Result.country_id IS NOT NULL, location_weight / score_order, 0)) AS locationScore, SUM(IF(Result.gender IS NOT NULL, gender_weight / score_order, 0)) AS genderScore,
						SUM(IF(Result.age_range_id IS NOT NULL, age_weight / score_order, 0)) AS ageScore, SUM(IF(Result.bonus_coupon_id IS NOT NULL, bonus_coupon_weight / score_order, 0)) AS bonusCouponScore  
				FROM gaming_clients
				JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id
				JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id
				LEFT JOIN (
				-- COUNTRY --
				SELECT country_id,NULL AS gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max,  NULL AS bonus_coupon_id, game_id, amountScore, score_order 
				FROM (SELECT country_id, Intermediate.game_id, amountScore, IF(country_id != @countryID, @counter := 1, @counter := @counter + 1) AS orderNum, @counter AS score_order, IF(country_id != @countryID, @countryID := country_id, 0)
					FROM (SELECT cl.country_id, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id -- , location_weight As Weight
							FROM gaming_recommendations_intermediate_cache_top_games ggtapg
							JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
							JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
							JOIN clients_locations AS cl ON cl.client_id = gc.client_id AND cl.is_primary
							
							GROUP BY cl.country_id, game_id
							ORDER BY cl.country_id, amountScore DESC
						 ) Intermediate
					) Result
				GROUP BY country_id, Result.game_id
				UNION 
				-- GENDER --
				SELECT NULL AS country_id, gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max,  NULL AS bonus_coupon_id, game_id, amountScore, score_order 
				FROM (SELECT gender, Intermediate.game_id, amountScore, IF(gender != @gender, @counter := 1, @counter := @counter + 1) AS orderNum, @counter AS score_order, IF(gender != @gender, @gender := gender, 0)
					FROM (SELECT gender, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id 
							FROM gaming_recommendations_intermediate_cache_top_games ggtapg
							JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
							JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
							GROUP BY gender, game_id
							ORDER BY gender, amountScore DESC
						 ) Intermediate
				) Result
				GROUP BY gender, Result.game_id
				UNION
				-- AGE --
				SELECT NULL AS country_id, NULL AS gender, age_range_id, age_min, age_max, NULL AS bonus_coupon_id, game_id, amountScore, score_order
				FROM (SELECT age_range_id, age_min, age_max, game_id, amountScore, score_order 
					FROM (SELECT age_range_id, age_min, age_max, Intermediate.game_id, amountScore, IF(age_range_id != @age_range, @counter := 1, @counter := @counter + 1) AS orderNum,  @counter AS score_order, IF(age_range_id != @age_range, @age_range := age_range_id, 0)
						FROM (SELECT age_range_id, age_min, age_max, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id 
								FROM gaming_recommendations_intermediate_cache_top_games ggtapg
								JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
								JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
								JOIN gaming_recommendations_age_ranges AS grar ON DATE_FORMAT(NOW(), '%Y') - DATE_FORMAT(gc.dob, '%Y') - (DATE_FORMAT(NOW(), '00-%m-%d') < DATE_FORMAT(gc.dob, '00-%m-%d')) BETWEEN age_min AND age_max
								GROUP BY age_range_id, game_id
								ORDER BY age_range_id, amountScore DESC
							 ) Intermediate
						) Result
				) Result1
				GROUP BY age_range_id, Result1.game_id
				UNION
				-- Bonus Coupon --
				SELECT NULL AS country_id, NULL AS gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max, bonus_coupon_id, game_id, preference, 1 AS score_order
				FROM gaming_recommendations_games_bonus_coupon
				GROUP BY bonus_coupon_id, game_id)
				 Result ON gaming_clients.gender = Result.gender OR clients_locations.country_id = Result.country_id OR DATE_FORMAT(NOW(), '%Y') - DATE_FORMAT(gaming_clients.dob, '%Y') - (DATE_FORMAT(NOW(), '00-%m-%d') < DATE_FORMAT(gaming_clients.dob, '00-%m-%d')) BETWEEN Result.age_min AND Result.age_max 
							OR gaming_clients.bonus_coupon_id = Result.bonus_coupon_id

				JOIN gaming_client_segments_players AS gcsp ON gcsp.client_id = gaming_clients.client_id
				JOIN gaming_recommendations_profiles AS grp ON grp.client_segment_id = gcsp.client_segment_id AND grp.is_current
				WHERE client_stat_id = clientStatID
				GROUP BY client_stat_id, gameId
				ORDER BY client_stat_id, gameId
				) Done
			);

			-- Log Scores
			INSERT INTO `gaming_recommendations_log_player`
			(`client_stat_id`,
			`game_id`,
			`location_score`,
			`gender_score`,
			`age_score`,
			`bonus_coupon_score`,
			`peer_game_activity_score`,
			`date_added`)
			SELECT *
			FROM log_temp_table
			WHERE client_stat_id = clientStatID;   
		
			SELECT clientStatID AS client_stat_id, gameId, ROUND(IFNULL((locationScore + genderScore + ageScore + bonusCouponScore),0.0),4) As Score
			FROM log_temp_table 
			WHERE client_stat_id = clientStatID; 

			DROP TABLE log_temp_table;

		ELSE  -- ----------------------------------------------------------------------------------------
			-- This is for a single client without logging. Typically executed on a client's first registration

			SELECT client_stat_id, gameId, ROUND(IFNULL((locationScore + genderScore + ageScore + bonusCouponScore),0.0),4) AS Score
			FROM (
			SELECT gaming_client_stats.client_stat_id, gaming_clients.client_id, Result.game_id AS gameId, SUM(IF(Result.country_id IS NOT NULL, location_weight / score_order, 0)) AS locationScore, SUM(IF(Result.gender IS NOT NULL, gender_weight / score_order, 0)) AS genderScore,
					SUM(IF(Result.age_range_id IS NOT NULL, age_weight / score_order, 0)) AS ageScore, SUM(IF(Result.bonus_coupon_id IS NOT NULL, bonus_coupon_weight / score_order, 0)) AS bonusCouponScore  
			FROM gaming_clients 
			JOIN gaming_client_stats ON gaming_clients.client_id = gaming_client_stats.client_id 
			JOIN clients_locations ON gaming_clients.client_id = clients_locations.client_id
			LEFT JOIN (
			-- COUNTRY --
			SELECT country_id,NULL AS gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max,  NULL AS bonus_coupon_id, game_id, amountScore, score_order 
			FROM (SELECT country_id, Intermediate.game_id, amountScore, IF(country_id != @countryID, @counter := 1, @counter := @counter + 1) AS orderNum, @counter AS score_order, IF(country_id != @countryID, @countryID := country_id, 0)
				FROM (SELECT cl.country_id, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id -- , location_weight As Weight
						FROM gaming_recommendations_intermediate_cache_top_games ggtapg
						JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
						JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
						JOIN clients_locations AS cl ON cl.client_id = gc.client_id AND cl.is_primary
						
						GROUP BY cl.country_id, game_id
						ORDER BY cl.country_id, amountScore DESC
					 ) Intermediate
				) Result
			GROUP BY country_id, Result.game_id
			UNION 
			-- GENDER --
			SELECT NULL AS country_id, gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max,  NULL AS bonus_coupon_id, game_id, amountScore, score_order 
			FROM (SELECT gender, Intermediate.game_id, amountScore, IF(gender != @gender, @counter := 1, @counter := @counter + 1) AS orderNum, @counter AS score_order, IF(gender != @gender, @gender := gender, 0)
				FROM (SELECT gender, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id 
						FROM gaming_recommendations_intermediate_cache_top_games ggtapg
						JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
						JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
						GROUP BY gender, game_id
						ORDER BY gender, amountScore DESC
					 ) Intermediate
			) Result
			GROUP BY gender, Result.game_id
			UNION
			-- AGE --
			SELECT NULL AS country_id, NULL AS gender, age_range_id, age_min, age_max, NULL AS bonus_coupon_id, game_id, amountScore, score_order
			FROM (SELECT age_range_id, age_min, age_max, game_id, amountScore, score_order 
				FROM (SELECT age_range_id, age_min, age_max, Intermediate.game_id, amountScore, IF(age_range_id != @age_range, @counter := 1, @counter := @counter + 1) AS orderNum,  @counter AS score_order, IF(age_range_id != @age_range, @age_range := age_range_id, 0)
					FROM (SELECT age_range_id, age_min, age_max, ggtapg.client_stat_id, SUM(amount) AS amountScore, game_id 
							FROM gaming_recommendations_intermediate_cache_top_games ggtapg
							JOIN gaming_client_stats AS gcs ON gcs.client_stat_id = ggtapg.client_stat_id
							JOIN gaming_clients AS gc ON gc.client_id = gcs.client_id
							JOIN gaming_recommendations_age_ranges AS grar ON DATE_FORMAT(NOW(), '%Y') - DATE_FORMAT(gc.dob, '%Y') - (DATE_FORMAT(NOW(), '00-%m-%d') < DATE_FORMAT(gc.dob, '00-%m-%d')) BETWEEN age_min AND age_max
							GROUP BY age_range_id, game_id
							ORDER BY age_range_id, amountScore DESC
						 ) Intermediate
					) Result
			) Result1
			GROUP BY age_range_id, Result1.game_id
			UNION
			-- Bonus Coupon --
			SELECT NULL AS country_id, NULL AS gender, NULL AS age_range_id, NULL AS age_min, NULL AS age_max, bonus_coupon_id, game_id, preference, 1 AS score_order   -- this is 1 as the order is not necessary
			FROM gaming_recommendations_games_bonus_coupon
			GROUP BY bonus_coupon_id, game_id)
			 Result ON gaming_clients.gender = Result.gender OR clients_locations.country_id = Result.country_id OR DATE_FORMAT(NOW(), '%Y') - DATE_FORMAT(gaming_clients.dob, '%Y') - (DATE_FORMAT(NOW(), '00-%m-%d') < DATE_FORMAT(gaming_clients.dob, '00-%m-%d')) BETWEEN Result.age_min AND Result.age_max 
						OR gaming_clients.bonus_coupon_id = Result.bonus_coupon_id

			JOIN gaming_client_segments_players AS gcsp ON gcsp.client_id = gaming_clients.client_id
			JOIN gaming_recommendations_profiles AS grp ON grp.client_segment_id = gcsp.client_segment_id AND grp.is_current
			WHERE client_stat_id = clientStatID
			GROUP BY client_stat_id, gameId
			ORDER BY client_stat_id, gameId
			) Done;

		END IF;
	END IF;
ELSE 
  SET statusCode = 1;
END IF;

END$$

DELIMITER ;

