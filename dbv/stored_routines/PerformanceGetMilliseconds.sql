DROP function IF EXISTS `PerformanceGetMilliseconds`;

DELIMITER $$
CREATE DEFINER=`root`@`127.0.0.1` FUNCTION `PerformanceGetMilliseconds`() RETURNS bigint(20)
BEGIN

	-- Brian :)

	RETURN ROUND(UNIX_TIMESTAMP(CURTIME(4)) * 1000);

END$$

DELIMITER ;

