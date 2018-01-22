DROP procedure IF EXISTS `PlayLimitsUpdateWithGame`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitsUpdateWithGame`(sessionID BIGINT, clientStatID BIGINT, licenseType VARCHAR(20), transactionAmount DECIMAL(18,5), isBet tinyint(1), gameID BIGINT)
BEGIN
    -- Added Game Level  

    SELECT PlayLimitsUpdateFunc(sessionID, clientStatID, licenseType, transactionAmount, isBet, gameID) INTO @erroCount;

END$$

DELIMITER ;

