DROP procedure IF EXISTS `PlayLimitsUpdate`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` PROCEDURE `PlayLimitsUpdate`(clientStatID BIGINT, licenseType VARCHAR(20), transactionAmount DECIMAL(18,5), isBet tinyint(1))
BEGIN
	SELECT PlayLimitsUpdateFunc(NULL, clientStatID, licenseType, transactionAmount, isBet, NULL) INTO @erroCount; 
END$$

DELIMITER ;

