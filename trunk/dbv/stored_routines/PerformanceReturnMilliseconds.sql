DROP function IF EXISTS `PerformanceReturnMilliseconds`;

DELIMITER $$
CREATE DEFINER=`root`@`127.0.0.1` FUNCTION `PerformanceReturnMilliseconds`() RETURNS varchar(60) CHARSET utf8
BEGIN
	-- Brian :)

	DECLARE diffMs BIGINT DEFAULT 0;  

	IF (@performanceCounter IS NULL) THEN

		SET @performanceCounter=0;
        SET @sysDate1=PerformanceGetMilliseconds();

		SET diffMs=-1;

	ELSE

		SET @sysDateCur=PerformanceGetMilliseconds();
    
		SET diffMs=@sysDateCur-@sysDate1;

		SET @sysDate1=@sysDateCur;

	END IF;

	SET @performanceCounter = @performanceCounter+1;

	RETURN CONCAT(@performanceCounter, ': ', diffMs);
    
END$$

DELIMITER ;

