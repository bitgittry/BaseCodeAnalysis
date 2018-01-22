DROP function IF EXISTS `DateOnlyGetYearStart`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `DateOnlyGetYearStart`(check_date DATE) RETURNS date
BEGIN
    -- First Version
	SET check_date = IFNULL(check_date, CURRENT_DATE);
	RETURN DATE_FORMAT(check_date ,'%Y-01-01');
END$$

DELIMITER ;

