DROP function IF EXISTS `CreatePromotionOccurrences`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CreatePromotionOccurrences`(recurrenceType VARCHAR(10), promotionID BIGINT(20), weekInterval int(11), durationMinutes BIGINT(10), startDate DATETIME, endDate DATETIME, startTime VARCHAR(10)) RETURNS int(11)
BEGIN

DECLARE recurrenceTimes, remainingRecurrences BIGINT DEFAULT 0;

-- Generate dates for occurrences
SET @recurrenceCount = 0;
SET @latestDate = null;
SET @lookaheadMonths = 3;
SET @dayNum = 0;

SELECT IFNULL((SELECT start_date 
FROM gaming_promotions_recurrence_dates
WHERE gaming_promotions_recurrence_dates.promotion_id = promotionID
ORDER BY gaming_promotions_recurrence_dates.start_date DESC
LIMIT 1), startDate)
INTO @latestDate;
 
SELECT value_int 
INTO @lookaheadMonths
FROM gaming_settings
WHERE name = 'PROMOTIONS_RECURRENCE_LOOKAHEAD_CREATION';

SELECT IFNULL(recurrence_times, 999999999) INTO recurrenceTimes FROM gaming_promotions WHERE promotion_id = promotionID;
SELECT COUNT(*) INTO remainingRecurrences FROM gaming_promotions_recurrence_dates WHERE promotion_id = promotionID;

SET @recurrenceCount = IFNULL(remainingRecurrences, 0);
SET remainingRecurrences = recurrenceTimes - remainingRecurrences;
SET @latestDate = concat(date(@latestDate), ' 00:00:00');  -- Set to beginning of day to accept today's occurrence.

CASE recurrenceType  
	WHEN 1 THEN  -- Daily 
		INSERT INTO gaming_promotions_recurrence_dates (promotion_id, recurrence_no, start_date, end_date, is_active, is_current)
		SELECT promotionID, @recurrenceCount := @recurrenceCount + 1 as recurrence_num, start_date_r, DATE_ADD(start_date_r, INTERVAL durationMinutes MINUTE) as end_date, 1, IF(@recurrenceCount = 1, 1, 0)
		FROM (SELECT 
			ADDTIME(date_from, startTime) as start_date_r, (@dayNum := @dayNum + 1)  - 1 as occ_num, @dayNum, gaming_promotions.recurrency_pattern_every_num
			FROM gaming_query_date_intervals 
			JOIN gaming_promotions ON promotionID = gaming_promotions.promotion_id
			WHERE query_date_interval_type_id = 3 AND (date_from BETWEEN @latestDate AND endDate) AND date_from <= DATE_ADD(NOW(), INTERVAL @lookaheadMonths MONTH)			
			ORDER BY start_date_r
			) Sub
		 WHERE (occ_num % Sub.recurrency_pattern_every_num) = 0
		 LIMIT remainingRecurrences;
	WHEN 2 THEN -- WEEKLY
		INSERT INTO gaming_promotions_recurrence_dates (promotion_id, recurrence_no, start_date, end_date, is_active, is_current)
		SELECT promotionID, @recurrenceCount := @recurrenceCount + 1 as recurrence_num, start_date_r, DATE_ADD(start_date_r, INTERVAL durationMinutes MINUTE) as end_date, 1, IF(@recurrenceCount = 1, 1, 0)
		FROM (SELECT DISTINCT
			ADDTIME(DATE_ADD(date_from ,INTERVAL (day_no-DAYOFWEEK(date_from)) DAY), startTime) as start_date_r, WEEK(date_from) - WEEK(@latestDate) as occ_num
			FROM gaming_query_date_intervals 
			JOIN gaming_promotions_recurrence_days ON promotionID = gaming_promotions_recurrence_days.promotion_id
			JOIN gaming_promotions ON promotionID = gaming_promotions.promotion_id
			WHERE query_date_interval_type_id = 3 AND ((WEEK(date_from) - WEEK(@latestDate)) % gaming_promotions.recurrency_pattern_every_num = 0) AND date_from <= DATE_ADD(NOW(), INTERVAL @lookaheadMonths MONTH)	
			ORDER BY start_date_r) Sub 
		WHERE start_date_r BETWEEN @latestDate AND endDate
		LIMIT remainingRecurrences;  
END CASE; 

RETURN 1;
END$$

DELIMITER ;

