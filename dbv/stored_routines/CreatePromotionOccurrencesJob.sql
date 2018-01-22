 
DROP procedure IF EXISTS `CreatePromotionOccurrencesJob`;

DELIMITER $$
 
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `CreatePromotionOccurrencesJob`()
BEGIN

	DECLARE finished, correct INTEGER DEFAULT 0;
	DECLARE recurrenceType, startTime VARCHAR(10) DEFAULT NULL;
	DECLARE promotionID, durationMinutes VARCHAR(10) DEFAULT NULL;
	DECLARE weekInterval INT(11) DEFAULT 1;
	DECLARE startDate, endDate DATETIME DEFAULT NULL;
    
	-- declare cursor for promotions
	DEClARE promotionCursor CURSOR FOR 
		SELECT recurrence_pattern_interval_type, promotion_id, recurrency_pattern_every_num, recurrence_duration_minutes, achievement_start_date, achievement_end_date, recurrence_start_time
		FROM gaming_promotions WHERE recurrence_enabled = 1 AND is_hidden = 0 ;
        -- AND achievement_end_date >= DATE_ADD(NOW(), INTERVAL IFNULL((SELECT value_int FROM gaming_settings WHERE name = 'PROMOTIONS_RECURRENCE_LOOKAHEAD_CREATION'), 3) MONTH); 
		
	-- declare NOT FOUND handler
	DECLARE CONTINUE HANDLER 
		FOR NOT FOUND SET finished = 1; 

	OPEN promotionCursor;
    
	promotions: LOOP 
   
	 SET finished = 0;
	 FETCH promotionCursor INTO recurrenceType, promotionID, weekInterval, durationMinutes, startDate, endDate, startTime;
	
     IF finished = 1 THEN 
		LEAVE promotions;
	 END IF;
	
	-- Retrieve the recurring promotions whose occurrences must be updated.
	SET correct = CreatePromotionOccurrences(recurrenceType, promotionID, weekInterval, durationMinutes, startDate, endDate, startTime);

	END LOOP promotions;

	CLOSE promotionCursor;

END$$

DELIMITER ;

