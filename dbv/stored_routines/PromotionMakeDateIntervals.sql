DROP procedure IF EXISTS `PromotionMakeDateIntervals`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PromotionMakeDateIntervals`(promotionID BIGINT, deletePrevious INT, intVal INT, unitVal VARCHAR(10), OUT statusCode INT)
root:BEGIN
  
  DECLARE promotionIDCheck BIGINT DEFAULT -1;
  DECLARE countPrevious INT DEFAULT 0;
  DECLARE startDate, endDate DATETIME;
  DECLARE isParent, isRecurrence TINYINT(1) DEFAULT 0;
  
  SET statusCode=10;
  
  
  SELECT promotion_id, achievement_start_date, achievement_end_date, is_parent, recurrence_enabled
  INTO promotionIDCheck, startDate, endDate, isParent, isRecurrence
  FROM gaming_promotions 
  WHERE promotion_id=promotionID;
 
  SET startDate = DATE(startdate);
  SET endDate = endDate; 
 
  
  IF (promotionID=-1) THEN
    SET statusCode=1;
    LEAVE root;
  END IF;
   
  
  IF (deletePrevious=1) THEN 
    DELETE FROM gaming_promotions_status_days 
    WHERE promotion_id=promotionID;
  END IF;
  
  SELECT IFNULL(COUNT(promotion_status_day_id),0) INTO countPrevious   
  FROM gaming_promotions_status_days 
  WHERE promotion_id=promotionID;
  
  IF (countPrevious<>0) THEN
    SET statusCode=2;
    LEAVE root;
  END IF;
  
  SET @dayNo=0;
  SET @promotionRecurrenceDateID=0;
  IF(isRecurrence = 0) THEN
	  INSERT INTO gaming_promotions_status_days (promotion_id, day_no, day_start_time, day_end_time, date_display, query_date_interval_id) 
	  SELECT promotionID, @dayNo:=@dayNo+1, intervals.date_from, intervals.date_to, intervals.date_display, intervals.query_date_interval_id
	  FROM gaming_query_date_interval_types AS interval_type 
	  JOIN gaming_query_date_intervals AS intervals ON interval_type.name=unitVal AND
	  (intervals.date_from BETWEEN DATE(startDate) AND endDate) AND intervals.query_date_interval_type_id=interval_type.query_date_interval_type_id;
  ELSE
	  INSERT INTO gaming_promotions_status_days (promotion_id, day_no, day_start_time, day_end_time, date_display, query_date_interval_id, promotion_recurrence_date_id) 
	  SELECT promotionID, @dayNo:=IF(promotion_recurrence_date_id!=@promotionRecurrenceDateID, 1, @dayNo+1), date_from, date_to, date_display, query_date_interval_id, @promotionRecurrenceDateID:=promotion_recurrence_date_id
	  FROM (
		  SELECT intervals.date_from, intervals.date_to, intervals.date_display, intervals.query_date_interval_id, recurrece_dates.promotion_recurrence_date_id
		  FROM gaming_promotions_recurrence_dates AS recurrece_dates
		  JOIN gaming_query_date_interval_types AS interval_type ON interval_type.name=unitVal 
		  JOIN gaming_query_date_intervals AS intervals ON (intervals.date_from BETWEEN DATE(recurrece_dates.start_date) AND recurrece_dates.end_date) AND intervals.query_date_interval_type_id=interval_type.query_date_interval_type_id
		  WHERE recurrece_dates.promotion_id=promotionID
		  ORDER BY recurrece_dates.recurrence_no ASC, intervals.date_interval_num
	  ) AS XX;

  END IF;

  SET @child_day_no=1;
  SET @child_promotion_id=-1;
  
  -- To remove
  IF (isParent=1) THEN
    UPDATE gaming_promotions_status_days AS days
    JOIN
    (
      SELECT days.promotion_status_day_id, @child_day_no:=IF(gaming_promotions.promotion_id!=@child_promotion_id, 1, @child_day_no+1) AS child_day_no, @child_promotion_id:=IF(gaming_promotions.promotion_id!=@child_promotion_id, gaming_promotions.promotion_id, @child_promotion_id) AS child_promotion_id
      FROM gaming_promotions
      JOIN gaming_promotions_status_days AS days ON 
        gaming_promotions.parent_promotion_id=promotionID AND days.promotion_id=gaming_promotions.parent_promotion_id AND 
        (gaming_promotions.achievement_start_date<days.day_end_time AND gaming_promotions.achievement_end_date>days.day_start_time)
      ORDER BY gaming_promotions.promotion_id, day_no
    ) AS child_days ON days.promotion_status_day_id=child_days.promotion_status_day_id
    SET days.child_promotion_id=child_days.child_promotion_id, days.child_day_no=child_days.child_day_no;
  END IF;
  SET statusCode=0;
END root$$

DELIMITER ;

