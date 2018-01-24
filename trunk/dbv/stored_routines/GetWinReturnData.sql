DROP procedure IF EXISTS `GetWinReturnData`;

DELIMITER $$
CREATE DEFINER=`root`@`localhost` PROCEDURE `GetWinReturnData`(
  extraID BIGINT,licenseTypeID BIGINT, roundID BIGINT,clientStatID BIGINT,gameManufacturerID BIGINT)
BEGIN

	CALL PlayReturnDataWithoutGameForSbExtraID(extraID, licenseTypeID, roundID, clientStatID, gameManufacturerID, 0);
	CALL PlayReturnBonusInfoOnWinForSbExtraID(extraID, licenseTypeID); 

END$$

DELIMITER ;

