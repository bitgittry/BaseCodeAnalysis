DROP function IF EXISTS `PlayLimitCheckExceeded`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayLimitCheckExceeded`(transactionAmount DECIMAL(18, 5), sessionID BIGINT, clientStatID BIGINT, licenseType VARCHAR(20)) RETURNS tinyint(1)
    DETERMINISTIC
BEGIN
  RETURN PlayLimitCheckExceededWithGame(transactionAmount, sessionID, clientStatID, licenseType, NULL);
END$$

DELIMITER ;

