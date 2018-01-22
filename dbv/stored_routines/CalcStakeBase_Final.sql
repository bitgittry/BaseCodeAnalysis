
DROP function IF EXISTS `CalcStakeBase_Final`;
DROP function IF EXISTS `CalcStakeRealBase_Final`;
DROP function IF EXISTS `CalcStakeBonusBase_Final`;
DROP function IF EXISTS `CalcStakeRealBase_Final_Singles`;
DROP function IF EXISTS `CalcStakeRealBase_Final_Multiples`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcStakeBase_Final`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN
	
    DECLARE originalAmount, adjustmentAmount, finalAmount DECIMAL(18, 2) DEFAULT 0.00;
	
	SET originalAmount = CalcStakeBase_Original(sbEntityID, entityType, isBonus);
	SET adjustmentAmount = CalcStakeBase_Adjustment(sbEntityID, entityType, isBonus);
	SET finalAmount = ROUND(originalAmount + adjustmentAmount, 2);

    RETURN finalAmount;

END$$

DELIMITER ;
