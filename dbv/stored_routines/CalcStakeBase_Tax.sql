
DROP function IF EXISTS `CalcStakeBase_Tax`;
DROP function IF EXISTS `CalcStakeRealBase_Tax`;
DROP function IF EXISTS `CalcStakeBonusBase_Tax`;
DROP function IF EXISTS `CalcStakeRealBase_Tax_Singles`;
DROP function IF EXISTS `CalcStakeRealBase_Tax_Multiples`;

DELIMITER $$
CREATE DEFINER=`bit8_admin`@`127.0.0.1` FUNCTION `CalcStakeBase_Tax`(sbEntityID BIGINT(11), entityType VARCHAR(10), isBonus TINYINT(1)) RETURNS decimal(18,2)
BEGIN

	-- betslip
	-- IF(entityType IS NULL) THEN
	
	-- singles
	-- ELSEIF(entityType = 'Singles') THEN
	
	-- multiples
	-- ELSEIF(entityType = 'Multiples') THEN
	
	-- END IF;
	
	RETURN NULL;

END$$

DELIMITER ;