DROP function IF EXISTS `DateGetMonthStart`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `DateGetMonthStart`() RETURNS datetime
BEGIN
--
	RETURN DATE_FORMAT(NOW() ,'%Y-%m-01');
END$$

DELIMITER ;

