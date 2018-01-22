DROP function IF EXISTS `QueryDatesGetDisplayDate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `QueryDatesGetDisplayDate`(thisDate DATETIME) RETURNS varchar(40) CHARSET utf8
BEGIN
  -- Catering for corner cases for years
  DECLARE thisDateNew, nextDate DATETIME DEFAULT NULL;

  SET thisDateNew=DateOnlyGetWeekStart(thisDate);	
  SET nextDate = DATE_ADD(DATE_ADD(thisDateNew, INTERVAL 1 WEEK), INTERVAL -1 SECOND);
  
  IF (YEAR(thisDateNew)<>YEAR(nextDate)) THEN 
	IF (YEAR(thisDate)>YEAR(thisDateNew)) THEN
	  SET thisDateNew = DATE_FORMAT(nextDate,'%Y-01-01 00:00:00');	
	ELSE
	  SET nextDate = DATE_FORMAT(thisDateNew,'%Y-12-31 23:59:59');	
	END IF;
  END IF;
  
  RETURN CONCAT(DATE_FORMAT(thisDateNew, '%Y - W%u (%m-%d .. '),DATE_FORMAT(nextDate,'%m-%d'),')');
END$$

DELIMITER ;

