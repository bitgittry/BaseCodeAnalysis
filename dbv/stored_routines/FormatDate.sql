DROP function IF EXISTS `FormatDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `FormatDate`(arg_IntervalTypeId int, arg_Date DATETIME, arg_OffsetMinutes int) RETURNS varchar(20) CHARSET utf8
root:BEGIN 
DECLARE res VARCHAR(20); 
SET arg_Date = DATE_ADD(arg_Date, INTERVAL arg_OffsetMinutes MINUTE); 
SET res = 
( 
CASE arg_IntervalTypeId 
WHEN 2 THEN DATE_FORMAT(arg_Date, '%Y-%m-%d %H:00:00') 
WHEN 3 THEN DATE_FORMAT(arg_Date, '%Y-%m-%d') 
WHEN 4 THEN DATE_SUB(arg_Date, INTERVAL WEEKDAY(arg_Date) DAY) 
WHEN 5 THEN DATE_FORMAT(arg_Date, '%Y-%m-01')  
WHEN 6 THEN DATE_ADD(DATE_FORMAT(arg_Date, '%Y-01-01'), INTERVAL QUARTER(arg_Date) - 1 QUARTER) 
WHEN 7 THEN DATE_FORMAT(arg_Date, '%Y-01-01') 
ELSE arg_Date END 
); 
RETURN res; 
END 
root$$

DELIMITER ;

