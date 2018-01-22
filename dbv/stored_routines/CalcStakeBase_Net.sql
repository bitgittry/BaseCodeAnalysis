
DROP function IF EXISTS `CalcStakeBase_Net`;
DROP function IF EXISTS `CalcStakeRealBase_Net`;
DROP function IF EXISTS `CalcStakeBonusBase_Net`;
DROP function IF EXISTS `CalcStakeRealBase_Net_Singles`;
DROP function IF EXISTS `CalcStakeRealBase_Net_Multiples`;

DELIMITER $$

CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcStakeBase_Net`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN

	DECLARE netAmount DECIMAL(18, 2) DEFAULT 0.00;

	-- remove TAX if applicable
    SET netAmount = CalcStakeBase_Final(sbEntityID, entityType, isBonus);
    
    RETURN netAmount;

END$$

DELIMITER ;

