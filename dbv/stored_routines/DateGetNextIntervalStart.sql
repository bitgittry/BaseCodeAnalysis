DROP function IF EXISTS `DateGetNextIntervalStart`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `DateGetNextIntervalStart`(intervalType VARCHAR(20)) RETURNS datetime
BEGIN

    -- First Version 

	RETURN CASE intervalType
		WHEN 'Immediate' THEN NOW()
		WHEN 'Daily' THEN DATE_ADD(DATE(NOW()), INTERVAL 1 DAY)
		WHEN 'Weekly' THEN DATE_ADD(DateOnlyGetWeekStart(NOW()), INTERVAL 7 DAY)
		WHEN 'Monthly' THEN DATE_ADD(DateOnlyGetMonthStart(NOW()), INTERVAL 1 MONTH)
		WHEN 'Quarterly' THEN DATE_ADD(DateOnlyGetYearStart(NOW()), INTERVAL QUARTER(NOW()) QUARTER)
		WHEN 'Yearly' THEN DATE_ADD(DateOnlyGetYearStart(NOW()), INTERVAL 1 YEAR)
		ELSE DATE_ADD(DateOnlyGetYearStart(NOW()), INTERVAL 1 YEAR) -- Should never come here
	END;

END$$

DELIMITER ;

