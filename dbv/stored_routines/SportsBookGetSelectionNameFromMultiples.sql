DROP function IF EXISTS `SportsBookGetSelectionNameFromMultiples`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `SportsBookGetSelectionNameFromMultiples`(betSlipID BIGINT(20), sbEntry varchar(40))
  RETURNS varchar(200) CHARSET utf8

BEGIN

DECLARE numMulti, numSingles, entryCount BIGINT(20) DEFAULT 0;
DECLARE selectionName, sbSelectionEntry VARCHAR(200);
DECLARE hasSystemBet, hasMultipleBet TINYINT(4) DEFAULT 0;

SELECT -- check if bet has multiples
  num_multiplies, num_singles INTO numMulti, numSingles
FROM gaming_sb_bets
WHERE sb_bet_id = betSlipID;

SELECT 1
   INTO hasSystemBet
FROM gaming_game_rounds ggr
  JOIN gaming_sb_bet_multiples_singles gbs ON ggr.sb_bet_entry_id = gbs.sb_bet_multiple_id
  JOIN gaming_sb_multiple_types mt ON mt.sb_multiple_type_id = ggr.sb_extra_id
WHERE ggr.sb_bet_id = betSlipID
  AND ggr.sb_extra_id IS NOT NULL
  GROUP BY gbs.sb_bet_multiple_id, mt.num_events_required, mt.is_system_bet
  HAVING COUNT(DISTINCT(gbs.sb_bet_multiple_single_id)) > mt.num_events_required OR mt.is_system_bet = 1 LIMIT 1;

SELECT 1
   INTO hasMultipleBet
FROM gaming_game_plays_sb pls
  JOIN gaming_sb_bet_multiples_singles gbs ON pls.sb_bet_entry_id = gbs.sb_bet_multiple_id
  JOIN gaming_sb_multiple_types mt ON mt.sb_multiple_type_id = pls.sb_multiple_type_id
WHERE pls.sb_selection_id IS NULL AND mt.is_system_bet = 0 AND pls.sb_bet_id = betSlipID
  GROUP BY pls.sb_multiple_type_id , mt.num_events_required
  HAVING COUNT(DISTINCT(gbs.sb_bet_multiple_single_id)) = mt.num_events_required LIMIT 1;

IF(numMulti > 0) THEN -- return the count of the entry
    SELECT CASE sbEntry 
        WHEN 'Markets' THEN COUNT(DISTINCT gss.sb_market_id)
        WHEN 'Events' THEN COUNT(DISTINCT gss.sb_event_id)
        WHEN 'Groups' THEN COUNT(DISTINCT gss.sb_group_id)
        WHEN 'Regions' THEN COUNT(DISTINCT gss.sb_region_id)
        WHEN 'Sports' THEN COUNT(DISTINCT gss.sb_sport_id)
        WHEN 'Selections' THEN COUNT(DISTINCT gss.sb_selection_id)
        WHEN 'Categories' THEN CASE WHEN numSingles = 0 THEN 1 ELSE CASE WHEN hasSystemBet AND hasMultipleBet THEN 3 ELSE 2 END END -- accumulator can be alone or part at the same time(1) or system/accumulator + singles(2)
    END INTO entryCount
    FROM gaming_game_rounds ggr
    JOIN gaming_sb_bet_multiples_singles gbs ON ggr.sb_bet_entry_id = gbs.sb_bet_multiple_id
    JOIN gaming_sb_selections gss ON gbs.sb_selection_id = gss.sb_selection_id
    JOIN gaming_sb_multiple_types mt ON mt.sb_multiple_type_id = ggr.sb_extra_id
    WHERE ggr.sb_bet_id = betSlipID
		AND ggr.sb_extra_id IS NOT NULL
		AND gbs.sb_bet_multiple_id IS NOT NULL;
      
    IF(entryCount = 1) THEN -- if we are here we know for sure there is same entry for all selection - we show its name
		SELECT CASE sbEntry 
    			WHEN 'Groups' THEN gg.name
    			WHEN 'Regions' THEN gr.name
    			WHEN 'Sports' THEN gs.name
    			WHEN 'Categories' THEN CASE WHEN COUNT(gbs.sb_bet_multiple_single_id) = mt.num_events_required THEN 'Accumulator' ELSE CASE WHEN hasSystemBet AND hasMultipleBet THEN '2 Categories' ELSE 'System' END END
        END INTO selectionName
        FROM gaming_game_rounds ggr
        JOIN gaming_sb_multiple_types mt ON mt.sb_multiple_type_id = ggr.sb_extra_id
        JOIN gaming_sb_bet_multiples_singles gbs ON ggr.sb_bet_entry_id = gbs.sb_bet_multiple_id
        JOIN gaming_sb_selections gss ON gbs.sb_selection_id = gss.sb_selection_id
        JOIN gaming_sb_events ge ON gss.sb_event_id = ge.sb_event_id
        JOIN gaming_sb_markets gm ON gss.sb_market_id = gm.sb_market_id
        JOIN gaming_sb_groups gg ON gss.sb_group_id = gg.sb_group_id
        JOIN gaming_sb_regions gr ON gss.sb_region_id = gr.sb_region_id
        JOIN gaming_sb_sports gs ON gss.sb_sport_id = gs.sb_sport_id
        WHERE ggr.sb_bet_id = betSlipID
            AND ggr.sb_extra_id IS NOT NULL
        GROUP BY gbs.sb_bet_multiple_id LIMIT 1;

        RETURN selectionName;
    END IF;

ELSE -- return the name of the single
    SELECT
      CASE sbEntry 
       WHEN 'Markets' THEN IF (COUNT(DISTINCT gm.name) > 1, CONCAT(COUNT(DISTINCT gm.name), CONCAT(' ', sbEntry)), gm.name)
        WHEN 'Events' THEN IF (COUNT(DISTINCT ge.name) > 1, CONCAT(COUNT(DISTINCT ge.name), CONCAT(' ', sbEntry)), ge.name)
        WHEN 'Groups' THEN IF (COUNT(DISTINCT gg.name) > 1, CONCAT(COUNT(DISTINCT gg.name), CONCAT(' ', sbEntry)), gg.name)
        WHEN 'Regions' THEN IF (COUNT(DISTINCT gr.name) > 1, CONCAT(COUNT(DISTINCT gr.name), CONCAT(' ', sbEntry)), gr.name)
        WHEN 'Sports' THEN IF (COUNT(DISTINCT gs.name) > 1, CONCAT(COUNT(DISTINCT gs.name), CONCAT(' ', sbEntry)), gs.name)
        WHEN 'Selections' THEN IF (COUNT(DISTINCT gss.name) > 1, CONCAT(COUNT(DISTINCT gss.name), CONCAT(' ', sbEntry)), gss.name)
        WHEN 'Categories' THEN 'Singles'
      END INTO selectionName
    FROM gaming_game_plays_sb gps
    JOIN gaming_sb_selections gss ON gps.sb_selection_id = gss.sb_selection_id
    JOIN gaming_sb_events ge ON gss.sb_event_id = ge.sb_event_id
    JOIN gaming_sb_markets gm ON gss.sb_market_id = gm.sb_market_id
    JOIN gaming_sb_groups gg ON gss.sb_group_id = gg.sb_group_id
    JOIN gaming_sb_regions gr ON gss.sb_region_id = gr.sb_region_id
    JOIN gaming_sb_sports gs ON gss.sb_sport_id = gs.sb_sport_id
    WHERE gps.sb_bet_id = betSlipID
    GROUP BY gps.sb_bet_id;
	
    RETURN selectionName;
END IF;

RETURN CONCAT(CAST(entryCount AS CHAR), ' ', sbEntry);

END$$

DELIMITER ;

