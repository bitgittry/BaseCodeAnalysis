DROP procedure IF EXISTS `PromotionsSetCurrentOccurrencesJob`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionsSetCurrentOccurrencesJob`(promotionID BIGINT)
BEGIN

-- This job focuses on ensuring that the occurrences are always in a consistent state

-- Set the current occurence based on the following logic:
-- If the occurrence is within start date and end date, set current that occurrence which is the latest (newest start date)
-- If there are no valid occurrences (i.e. none between the start date and end date), set the next one to be the current occurrence. 
 
		UPDATE  
        (
			SELECT recur_dates.promotion_recurrence_date_id, recur_dates.promotion_id, recur_dates.recurrence_no, 
				recur_dates.start_date, recur_dates.end_date, MIN(recur_dates.recurrence_no) as curr_occurence_to_do
			FROM gaming_promotions FORCE INDEX (achievement_end_date_active)
            STRAIGHT_JOIN gaming_promotions_recurrence_dates AS recur_dates ON 
				gaming_promotions.promotion_id=recur_dates.promotion_id AND
                NOW() BETWEEN recur_dates.start_date AND recur_dates.end_date AND recur_dates.is_current=0
			WHERE gaming_promotions.is_active AND gaming_promotions.recurrence_enabled AND gaming_promotions.achievement_end_date>=NOW() AND
				(promotionID=0 OR gaming_promotions.promotion_id=promotionID)
			GROUP BY recur_dates.promotion_id
            HAVING MIN(recur_dates.recurrence_no) IS NOT NULL
		) AS XX 
        STRAIGHT_JOIN gaming_promotions_recurrence_dates ON 
			gaming_promotions_recurrence_dates.promotion_recurrence_date_id=XX.promotion_recurrence_date_id OR
            (gaming_promotions_recurrence_dates.promotion_id=XX.promotion_id AND gaming_promotions_recurrence_dates.is_current)
		SET is_current = (gaming_promotions_recurrence_dates.recurrence_no = XX.curr_occurence_to_do);
  
		-- If current occurence has expired then set it to the next
		UPDATE  
        (
			SELECT recur_dates.promotion_recurrence_date_id, recur_dates.promotion_id, recur_dates.recurrence_no, 
				recur_dates.start_date, recur_dates.end_date, MIN(recur_dates.recurrence_no) as curr_occurence_to_do
			FROM gaming_promotions FORCE INDEX (achievement_end_date_active)
            STRAIGHT_JOIN gaming_promotions_recurrence_dates AS recur_dates ON 
				gaming_promotions.promotion_id=recur_dates.promotion_id AND
                NOW() > recur_dates.end_date AND recur_dates.is_current=1
			WHERE gaming_promotions.is_active AND gaming_promotions.recurrence_enabled AND gaming_promotions.achievement_end_date>=NOW() AND
				(promotionID=0 OR gaming_promotions.promotion_id=promotionID)
			GROUP BY recur_dates.promotion_id
            HAVING MIN(recur_dates.recurrence_no) IS NOT NULL
		) AS XX 
        STRAIGHT_JOIN gaming_promotions_recurrence_dates AS current_occurence ON current_occurence.promotion_recurrence_date_id=XX.promotion_recurrence_date_id
        STRAIGHT_JOIN gaming_promotions_recurrence_dates ON 
            (gaming_promotions_recurrence_dates.promotion_id=XX.promotion_id AND gaming_promotions_recurrence_dates.recurrence_no=XX.curr_occurence_to_do+1)
		SET current_occurence.is_current = 0,
			gaming_promotions_recurrence_dates.is_current = 1;
  
END$$

DELIMITER ;

