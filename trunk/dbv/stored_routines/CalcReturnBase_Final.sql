
DROP function IF EXISTS `CalcReturnBase_Final`;
DROP function IF EXISTS `CalcReturnRealBase_Final`;
DROP function IF EXISTS `CalcReturnBonusBase_Final`;
DROP function IF EXISTS `CalcReturnRealBase_Final_Singles`;
DROP function IF EXISTS `CalcReturnRealBase_Final_Multiples`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcReturnBase_Final`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN

	DECLARE originalAmount, adjustmentAmount, finalAmount DECIMAL(18, 5) DEFAULT 0.00;

	SET originalAmount = CalcReturnBase_Original(sbEntityID, entityType, isBonus);
	SET adjustmentAmount = CalcReturnBase_Adjustment(sbEntityID, entityType, isBonus);
	SET finalAmount = ROUND(originalAmount + adjustmentAmount, 2);

    RETURN finalAmount;

END$$

DELIMITER ;
