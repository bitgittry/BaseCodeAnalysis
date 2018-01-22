
DROP function IF EXISTS `CalcReturnBase_Net`;
DROP function IF EXISTS `CalcReturnRealBase_Net`;
DROP function IF EXISTS `CalcReturnBonusBase_Net`;
DROP function IF EXISTS `CalcReturnRealBase_Net_Singles`;
DROP function IF EXISTS `CalcReturnRealBase_Net_Multiples`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcReturnBase_Net`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN

	DECLARE netAmount DECIMAL(18, 2) DEFAULT 0.00;

    SET netAmount = CalcReturnBase_Final(sbEntityID, entityType, isBonus) - CalcReturnBase_Tax(sbEntityID, entityType, isBonus);
    
    RETURN netAmount;

END$$

DELIMITER ;