DROP FUNCTION IF EXISTS `PlayLimitGetRollingLimitCurrentValue`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `PlayLimitGetRollingLimitCurrentValue`(clientStatID BIGINT, licenseType VARCHAR(20), channelType VARCHAR(50), adminLimit TINYINT(1)) RETURNS DECIMAL(18,5)
BEGIN
  DECLARE limitAmount, currentAmount DECIMAL(18,5) DEFAULT 0;
  DECLARE limitExists TINYINT(1) DEFAULT 0;

    CALL PlayLimitGetRollingLimitValues(clientStatID, licenseType, channelType, adminLimit, limitExists, limitAmount, currentAmount);

    RETURN currentAmount;

END$$

DELIMITER ;