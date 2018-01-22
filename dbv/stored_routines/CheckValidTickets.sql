DROP function IF EXISTS `CheckValidTickets`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CheckValidTickets`(pbBetId BIGINT, pd_pool_id BIGINT) RETURNS tinyint(1)
    READS SQL DATA
    DETERMINISTIC
BEGIN
    DECLARE numFix INT;
    DECLARE numValid INT;
    DECLARE hasConsolation INT;
    DECLARE validTicket, isHDA TINYINT(1) DEFAULT NULL;

-- NUM FIXTURES
SELECT 
    COUNT(*)
INTO numFix FROM
    gaming_pb_pool_fixtures
        LEFT JOIN
    gaming_pb_pools ON gaming_pb_pools.pb_pool_id = gaming_pb_pool_fixtures.pb_pool_id
WHERE
    gaming_pb_pools.pb_pool_id = pd_pool_id;
    
-- CHECK FOR CONSOLATION AND HDA
SELECT 
      IF(guarantee_consolation > 0, 1, 0)
	, IF(gaming_pb_pools.pb_pool_type_id BETWEEN 101 AND 200, 1, 0) -- all HDA types
INTO hasConsolation, isHDA
FROM
    gaming_pb_pools
WHERE
    pb_pool_id = pd_pool_id;    
        
-- NUM VALID
IF hasConsolation = 0 AND isHDA = 0 THEN
SELECT 
    COUNT(*)
INTO numValid FROM
    (SELECT * FROM
		(SELECT 
			gaming_pb_fixtures.pb_fixture_id,
				CASE
					WHEN
						fixtures.poolStatus = 'OPEN'
							OR fixtures.poolStatus = 'ABANDONED'
							OR fixtures.poolStatus = 'POSTPONED'
					THEN
						'Valid'
					WHEN
						fixtures.poolStatus = 'STARTED'
							OR fixtures.poolStatus = 'HALF_TIME'
							OR fixtures.poolStatus = 'SECOND_HALF'
					THEN
						CASE
							WHEN
								gaming_pb_outcomes.name = 'AOH'
									OR gaming_pb_outcomes.name = 'AOD'
									OR gaming_pb_outcomes.name = 'AOA'
							THEN
								'Valid'
							WHEN
								SPLIT_STR(gaming_pb_outcomes.name, '-', 1) >= SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1)
									AND SPLIT_STR(gaming_pb_outcomes.name, '-', 2) >= SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
							THEN
								'Valid'
							ELSE 'Not Valid'
						END
					WHEN
						fixtures.poolStatus = 'COMPLETED'
							OR fixtures.poolStatus = 'OFFICIAL'
					THEN
						CASE
							WHEN
								SPLIT_STR(gaming_pb_outcomes.name, '-', 1) = SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1)
									AND SPLIT_STR(gaming_pb_outcomes.name, '-', 2) = SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
							THEN
								'Valid'
							WHEN
								gaming_pb_outcomes.name = 'AOH'
							THEN
								IF((SELECT 
										COUNT(*)
									FROM
										gaming_pb_outcomes
									WHERE
										gaming_pb_outcomes.name = gaming_pb_fixtures.current_score) > 0, 'Not Valid',  IF(SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) > 3 AND SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) > SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2), 'Valid', 'Not Valid'))
							WHEN
								gaming_pb_outcomes.name = 'AOD'
							THEN
								IF((SELECT 
										COUNT(*)
									FROM
										gaming_pb_outcomes
									WHERE
										gaming_pb_outcomes.name = gaming_pb_fixtures.current_score) > 0, 'Not Valid', IF(SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) > 2
											AND SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)  > 2
											AND SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) = SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2), 'Valid', 'Not Valid'))
							WHEN
								gaming_pb_outcomes.name = 'AOA'
							THEN
								IF((SELECT 
										COUNT(*)
									FROM
										gaming_pb_outcomes
									WHERE
										gaming_pb_outcomes.name = gaming_pb_fixtures.current_score) > 0, 'Not Valid', IF(SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) < SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
											AND SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2) > 3, 'Valid', 'Not Valid'))
						END
				END is_ticket_valid
		FROM
			gaming_game_plays_pb
		INNER JOIN gaming_pb_fixtures ON gaming_game_plays_pb.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
		INNER JOIN gaming_pb_outcomes ON gaming_game_plays_pb.pb_outcome_id = gaming_pb_outcomes.pb_outcome_id
		INNER JOIN gaming_pb_bets ON gaming_game_plays_pb.game_play_id = gaming_pb_bets.game_play_id
		INNER JOIN (SELECT 
			gaming_pb_fixtures.pb_fixture_id,
				gaming_pb_pools.pb_pool_id,
				gaming_pb_fixture_statuses.name AS poolStatus
		FROM
			gaming_pb_fixtures
		JOIN gaming_pb_fixture_statuses ON gaming_pb_fixtures.pb_fixture_status_id = gaming_pb_fixture_statuses.pb_fixture_status_id
		JOIN gaming_pb_pool_fixtures pf ON pf.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
		JOIN gaming_pb_pools ON pf.pb_pool_id = gaming_pb_pools.pb_pool_id
		JOIN gaming_pb_pool_statuses ON gaming_pb_pools.pb_status_id = gaming_pb_pool_statuses.pb_status_id
		GROUP BY gaming_pb_fixtures.pb_fixture_id) fixtures ON fixtures.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
		WHERE
			gaming_pb_bets.pb_bet_id = pbBetId) ticket
		WHERE
			is_ticket_valid = 'Valid'
		GROUP BY ticket.pb_fixture_id) valid_fixtures;
ELSE -- CS/HDA CONSOLATION PRIZE
SELECT 
    COUNT(*)
INTO numValid FROM
    (SELECT * FROM (SELECT 
        gaming_pb_fixtures.pb_fixture_id,
            CASE
                WHEN
                    fixtures.poolStatus = 'COMPLETED'
                        OR fixtures.poolStatus = 'OFFICIAL'
                THEN
					CASE
						WHEN gaming_pb_outcomes.name = 'AOH' -- home wins
							THEN CASE WHEN SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) > SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
								THEN 'Valid'
								ELSE 'Not Valid'
							END
						WHEN gaming_pb_outcomes.name = 'AOD' -- draw
                            THEN CASE WHEN SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) = SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
								THEN 'Valid'		
								ELSE 'Not Valid'
							END
						WHEN gaming_pb_outcomes.name = 'AOA' -- away wins
							THEN CASE WHEN SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) < SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
								THEN 'Valid'
								ELSE 'Not Valid'
							END
						WHEN (SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) > SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
                                  AND SPLIT_STR(gaming_pb_outcomes.name, '-', 1) > SPLIT_STR(gaming_pb_outcomes.name, '-', 2))
                            OR (SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) = SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
                                  AND SPLIT_STR(gaming_pb_outcomes.name, '-', 1) = SPLIT_STR(gaming_pb_outcomes.name, '-', 2))
                            OR (SPLIT_STR(gaming_pb_fixtures.current_score, '-', 1) < SPLIT_STR(gaming_pb_fixtures.current_score, '-', 2)
                                  AND SPLIT_STR(gaming_pb_outcomes.name, '-', 1) < SPLIT_STR(gaming_pb_outcomes.name, '-', 2))
							THEN 'Valid'          
							ELSE 'Not Valid'
                    END
                ELSE 'Valid'
            END is_ticket_valid
    FROM
        gaming_game_plays_pb
    INNER JOIN gaming_pb_fixtures ON gaming_game_plays_pb.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
    INNER JOIN gaming_pb_outcomes ON gaming_game_plays_pb.pb_outcome_id = gaming_pb_outcomes.pb_outcome_id
    INNER JOIN gaming_pb_bets ON gaming_game_plays_pb.game_play_id = gaming_pb_bets.game_play_id
    INNER JOIN (SELECT 
        gaming_pb_fixtures.pb_fixture_id,
            gaming_pb_pools.pb_pool_id,
            gaming_pb_fixture_statuses.name AS poolStatus
    FROM
        gaming_pb_fixtures
    JOIN gaming_pb_fixture_statuses ON gaming_pb_fixtures.pb_fixture_status_id = gaming_pb_fixture_statuses.pb_fixture_status_id
    JOIN gaming_pb_pool_fixtures pf ON pf.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
    JOIN gaming_pb_pools ON pf.pb_pool_id = gaming_pb_pools.pb_pool_id
    JOIN gaming_pb_pool_statuses ON gaming_pb_pools.pb_status_id = gaming_pb_pool_statuses.pb_status_id
    GROUP BY gaming_pb_fixtures.pb_fixture_id) fixtures ON fixtures.pb_fixture_id = gaming_pb_fixtures.pb_fixture_id
    WHERE
        gaming_pb_bets.pb_bet_id = pbBetId) ticket
	WHERE
		is_ticket_valid = 'Valid'
		GROUP BY ticket.pb_fixture_id) valid_fixtures;
END IF;

    IF numValid = numFix THEN
      SET validTicket = 1;
    ELSE
      SET validTicket = 0;
    END IF;

    RETURN validTicket;
  END$$

DELIMITER ;

