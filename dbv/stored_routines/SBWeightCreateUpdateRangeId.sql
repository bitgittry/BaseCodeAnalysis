-- -------------------------------------
-- SBWeightCreateUpdateRangeId.sql
-- -------------------------------------
DROP FUNCTION IF EXISTS `SBWeightCreateUpdateRangeID`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `SBWeightCreateUpdateRangeID`(fromMultipleTypeId SMALLINT(6), toMultipleTypeId SMALLINT(6))
	RETURNS BIGINT(20)
BEGIN
	DECLARE rangeId BIGINT(20) DEFAULT NULL;
	
	IF (fromMultipleTypeId IS NOT NULL) THEN
		SELECT sb_weight_range_id INTO rangeId
		FROM gaming_sb_weight_profiles_weights_ranges
		WHERE sb_multiple_type_id_from = fromMultipleTypeId AND 
			  sb_multiple_type_id_to = toMultipleTypeId; 
		
		IF (rangeId IS NULL) THEN
			INSERT INTO gaming_sb_weight_profiles_weights_ranges 
				(sb_multiple_type_id_from, sb_multiple_type_id_to) 
				VALUES (fromMultipleTypeId, toMultipleTypeId);	
				
			SET rangeId=LAST_INSERT_ID();
		END IF;
	END IF;
	
	RETURN rangeId;
 
END$$

DELIMITER ;
