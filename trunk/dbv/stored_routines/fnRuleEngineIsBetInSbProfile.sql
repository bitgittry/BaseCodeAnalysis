DROP FUNCTION IF EXISTS `fnRuleEngineIsBetInSbProfile`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `fnRuleEngineIsBetInSbProfile`(arg_GamePlaySbId bigint, arg_ProfilesCsv varchar(2000)) RETURNS tinyint(1)
root:BEGIN

DECLARE res tinyint(1); 
DECLARE ct bigint(20); 
DECLARE gameManufacturerId INT;
DECLARE isSystemBet TINYINT(1);
DECLARE multipleName varchar(200);

  SELECT game_manufacturer_id INTO gameManufacturerId FROM gaming_game_plays_sb WHERE game_play_sb_id=arg_GamePlaySbId;
  
  SELECT gaming_sb_multiple_types.name,  gaming_sb_multiple_types.is_system_bet INTO  multipleName, isSystemBet
    from (SELECT sb_multiple_type_id FROM gaming_game_plays_sb where game_play_sb_id=arg_GamePlaySbId) gaming_game_plays_sb
    inner join gaming_sb_multiple_types on gaming_sb_multiple_types.sb_multiple_type_id=gaming_game_plays_sb.sb_multiple_type_id;
    
  SET res = 0;
  IF (lower(multipleName) IN ('single','singles')) THEN
    -- check singles hierarchy and weight ranges
    SELECT CASE WHEN COUNT(gaming_game_plays_sb.game_play_sb_id)>0 then 1 else -1 end into res FROM gaming_game_plays_sb 
    STRAIGHT_JOIN gaming_sb_bet_singles sing ON gaming_game_plays_sb.game_play_sb_id=arg_GamePlaySbId
    AND sing.sb_bet_single_id=gaming_game_plays_sb.sb_bet_entry_id 
    STRAIGHT_JOIN (select * from gaming_sb_weight_profiles where CONCAT(',',arg_ProfilesCsv,',') LIKE CONCAT('%,', CAST(sb_weight_profile_id AS CHAR), ',%') AND single_bet_allowed=1) rul 
    STRAIGHT_JOIN gaming_sb_weight_eligibility_criterias crit ON CONCAT(',',arg_ProfilesCsv,',') LIKE CONCAT('%,', CAST(crit.sb_weight_profile_id AS CHAR), ',%') 
    STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel1 
    ON crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND wsel1.sb_entity_type_id = 1 AND (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = gaming_game_plays_sb.sb_sport_id)
    STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel2 
    	ON crit.eligibility_criterias_id = wsel2.eligibility_criterias_id AND wsel2.sb_entity_type_id = 2 AND (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = gaming_game_plays_sb.sb_region_id)
    STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel3 
    	ON crit.eligibility_criterias_id = wsel3.eligibility_criterias_id AND wsel3.sb_entity_type_id = 3 AND (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = gaming_game_plays_sb.sb_group_id)
    STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel4 
    	ON crit.eligibility_criterias_id = wsel4.eligibility_criterias_id AND wsel4.sb_entity_type_id = 4 AND (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = gaming_game_plays_sb.sb_event_id)
    STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel5
    	ON crit.eligibility_criterias_id = wsel5.eligibility_criterias_id AND wsel5.sb_entity_type_id = 5 AND (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = gaming_game_plays_sb.sb_market_id)
    STRAIGHT_JOIN gaming_sb_weight_profiles_weights AS wght 
    			ON wsel5.eligibility_criterias_id = wght.eligibility_criterias_id
    			AND (sing.odd >= wght.min_odd AND (wght.max_odd IS NULL OR sing.odd < wght.max_odd)) 
          AND IFNULL(wght.weight, 0)>0
    			AND (rul.general_min_odd_per_selection IS NULL OR sing.odd >= rul.general_min_odd_per_selection);
  ELSE
      -- check if all the selections of the accumulator or system satisfy the sportbook profile hierarchy
      SELECT COUNT(*) INTO ct FROM (SELECT * FROM gaming_game_plays_sb WHERE game_play_sb_id=arg_GamePlaySbId) gaming_game_plays_sb
  		  STRAIGHT_JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_multiple_id=gaming_game_plays_sb.sb_bet_entry_id
  		  STRAIGHT_JOIN gaming_sb_bet_multiples_singles ON gaming_sb_bet_multiples_singles.sb_bet_multiple_id = gaming_sb_bet_multiples.sb_bet_multiple_id ;
             
      SELECT CASE WHEN count(*) = ct and ct>0 THEN 1 ELSE -2 END INTO res FROM (SELECT * FROM gaming_game_plays_sb WHERE game_play_sb_id=arg_GamePlaySbId) gaming_game_plays_sb
    		STRAIGHT_JOIN gaming_sb_bet_multiples ON gaming_sb_bet_multiples.sb_bet_multiple_id=gaming_game_plays_sb.sb_bet_entry_id
    		STRAIGHT_JOIN gaming_sb_bet_multiples_singles ON 
  			gaming_sb_bet_multiples_singles.sb_bet_multiple_id = gaming_sb_bet_multiples.sb_bet_multiple_id 
        STRAIGHT_JOIN gaming_sb_selections ON gaming_sb_selections.sb_selection_id =gaming_sb_bet_multiples_singles.sb_selection_id
        STRAIGHT_JOIN gaming_sb_weight_profiles rul ON CONCAT(',',arg_ProfilesCsv,',') LIKE CONCAT('%,', CAST(rul.sb_weight_profile_id AS CHAR), ',%') AND (accumulators_allowed=1 or system_bets_allowed=1)
        STRAIGHT_JOIN gaming_sb_weight_eligibility_criterias crit ON CONCAT(',',arg_ProfilesCsv,',') LIKE CONCAT('%,', CAST(crit.sb_weight_profile_id AS CHAR), ',%') 
        STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel1 
        ON crit.eligibility_criterias_id = wsel1.eligibility_criterias_id AND wsel1.sb_entity_type_id = 1 AND (wsel1.sb_entity_id IS NULL OR wsel1.sb_entity_id = gaming_sb_selections.sb_sport_id)
        STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel2 
        	ON crit.eligibility_criterias_id = wsel2.eligibility_criterias_id AND wsel2.sb_entity_type_id = 2 AND (wsel2.sb_entity_id IS NULL OR wsel2.sb_entity_id = gaming_sb_selections.sb_region_id)
        STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel3 
        	ON crit.eligibility_criterias_id = wsel3.eligibility_criterias_id AND wsel3.sb_entity_type_id = 3 AND (wsel3.sb_entity_id IS NULL OR wsel3.sb_entity_id = gaming_sb_selections.sb_group_id)
        STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel4 
        	ON crit.eligibility_criterias_id = wsel4.eligibility_criterias_id AND wsel4.sb_entity_type_id = 4 AND (wsel4.sb_entity_id IS NULL OR wsel4.sb_entity_id = gaming_sb_selections.sb_event_id)
        STRAIGHT_JOIN gaming_sb_weight_profile_selections AS wsel5
        	ON crit.eligibility_criterias_id = wsel5.eligibility_criterias_id AND wsel5.sb_entity_type_id = 5 AND (wsel5.sb_entity_id IS NULL OR wsel5.sb_entity_id = gaming_sb_selections.sb_market_id);
        
          IF (res=1) THEN
            IF (isSystemBet=0) THEN
              -- if the bet is not a system check if its type id is between the allowed ranges of multiple type ids. Range must have a weight greater than zero
              select CASE WHEN count(*) >0 THEN 1 ELSE -3 END INTO res from 
              (select gaming_sb_bet_multiples.sb_multiple_type_id from (select * from gaming_game_plays_sb where game_play_sb_id=arg_GamePlaySbId) gaming_game_plays_sb  inner join 
                gaming_sb_bet_multiples on gaming_sb_bet_multiples.sb_bet_id=gaming_game_plays_sb.sb_bet_id) dvtbl
                inner join
                (select gaming_sb_weight_profiles.sb_weight_profile_id, gaming_sb_weight_profiles_weights_ranges.sb_multiple_type_id_from, gaming_sb_weight_profiles_weights_ranges.sb_multiple_type_id_to from 
                  (select * from gaming_sb_weight_profiles 
                      where CONCAT(',',arg_ProfilesCsv,',') LIKE CONCAT('%,', CAST(sb_weight_profile_id AS CHAR), ',%') AND (accumulators_allowed=1 or system_bets_allowed=1)) gaming_sb_weight_profiles 
                inner join gaming_sb_weight_profiles_weights
                  on gaming_sb_weight_profiles_weights.sb_weight_profile_id=gaming_sb_weight_profiles.sb_weight_profile_id
                inner join gaming_sb_weight_profiles_weights_ranges on gaming_sb_weight_profiles_weights_ranges.sb_weight_range_id=gaming_sb_weight_profiles_weights.sb_weight_range_id
                  and gaming_sb_weight_profiles_weights.weight>0) dvtbl2
                on dvtbl.sb_multiple_type_id >= dvtbl2.sb_multiple_type_id_from
                and (dvtbl2.sb_multiple_type_id_to is null or dvtbl.sb_multiple_type_id<=dvtbl2.sb_multiple_type_id_to);
                
            ELSE
              select CASE WHEN count(*) >0 THEN 1 ELSE -4 END INTO res from 
                (select gaming_sb_bet_multiples.sb_multiple_type_id from (select * from gaming_game_plays_sb where game_play_sb_id=arg_GamePlaySbId) gaming_game_plays_sb  inner join 
                gaming_sb_bet_multiples on gaming_sb_bet_multiples.sb_bet_id=gaming_game_plays_sb.sb_bet_id) dvtbl
                inner join
                (select gaming_sb_weight_profiles.sb_weight_profile_id, gaming_sb_weight_profiles_weights.sb_multiple_type_id  from 
                  (select * from gaming_sb_weight_profiles 
                      where CONCAT(',',arg_ProfilesCsv,',') LIKE CONCAT('%,', CAST(sb_weight_profile_id AS CHAR), ',%') AND system_bets_allowed=1) gaming_sb_weight_profiles 
                inner join gaming_sb_weight_profiles_weights
                  on gaming_sb_weight_profiles_weights.sb_weight_profile_id=gaming_sb_weight_profiles.sb_weight_profile_id
                ) dvtbl2 on dvtbl2.sb_multiple_type_id=dvtbl.sb_multiple_type_id;
            END IF;
          END IF;
  END IF;
  


  RETURN res;
END$$

DELIMITER ;


