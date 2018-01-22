DROP function IF EXISTS `DayOfYearDateDif`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `DayOfYearDateDif`(curDate DATE, curSymbol CHAR(1), curParam INT(4)) RETURNS int(11)
    DETERMINISTIC
BEGIN
 	DECLARE curDayOfYear INT(4);
	DECLARE curResult INT(4);
	SET curDayOfYear = DAYOFYEAR(curDate);
		
	IF (curSymbol='+') THEN
		SET curResult = curDayOfYear + curParam;
		RETURN IF(curResult > 365, curResult - 365, curResult);
	ELSE
		SET curResult = curDayOfYear - curParam;
		RETURN IF(curResult < 0, 365 - curResult, curResult);
	END IF;
END$$

DELIMITER ;