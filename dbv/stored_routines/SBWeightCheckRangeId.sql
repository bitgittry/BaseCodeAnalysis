-- -------------------------------------
-- SBWeightCheckRangeID.sql
-- -------------------------------------
DROP FUNCTION IF EXISTS `SBWeightCheckRangeID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `SBWeightCheckRangeID`(multipleTypeId SMALLINT(6), rangeId BIGINT)
	RETURNS SMALLINT(6)
BEGIN
	DECLARE resultId SMALLINT(6) DEFAULT NULL;
	
  SELECT mResult.sb_multiple_type_id INTO resultId
  FROM gaming_sb_weight_profiles_weights_ranges AS rng
  JOIN gaming_sb_multiple_types AS mFrom 
        ON rng.sb_weight_range_id = rangeId AND rng.sb_multiple_type_id_from = mFrom.sb_multiple_type_id
  JOIN gaming_sb_multiple_types AS mResult 
        ON mFrom.game_manufacturer_id = mResult.game_manufacturer_id
  LEFT JOIN gaming_sb_multiple_types AS mTo 
        ON rng.sb_weight_range_id = rangeId AND rng.sb_multiple_type_id_to = mTo.sb_multiple_type_id    
  WHERE mResult.num_events_required >= mFrom.num_events_required 
        AND (mTo.sb_multiple_type_id IS NULL OR mResult.num_events_required <= mTo.num_events_required)
        AND mResult.sb_multiple_type_id = multipleTypeId; 
	
	RETURN resultId;
 
END$$

DELIMITER ;
